# `wt add` direnv auto-allow — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `wt add <branch>` auto-allow every `.envrc` in the new worktree (root + nested) by default, with a `--no-direnv` opt-out, so sub-agents and humans both land in a worktree with the dev shell already activated. Silently skip when `direnv` isn't on `PATH`.

**Architecture:** Two small bash helpers added to `pkgs/wt/default.nix` — `wt_find_envrcs` (lists relative paths of every `.envrc` under a given path, excluding `.git/`) and `wt_allow_envrcs` (loops the list through `direnv allow`, printing each as it goes). `cmd_add` calls them after `git worktree add`, gated by `command -v direnv` and a new `--no-direnv` flag parsed off the head of `"$@"`. Helpers are unit-tested by re-declaration in `pkgs/wt/tests/test-add-direnv.sh` (matching the existing `upstream_gone` pattern); `cmd_add` integration is manually smoke-tested.

**Tech Stack:** Nix (`writeShellApplication`), bash 5, `find`, `direnv`. No new dependencies.

**Reference spec:** `docs/superpowers/specs/2026-05-07-wt-add-direnv-auto-allow-design.md`.

---

## File Structure

- **Create:**
  - `pkgs/wt/tests/test-add-direnv.sh` — standalone integration test for both helpers, including a stubbed `direnv` on `PATH` to verify call args without depending on the real binary.

- **Modify:**
  - `pkgs/wt/default.nix` — add `wt_find_envrcs` and `wt_allow_envrcs` helpers; rewrite the head of `cmd_add` to parse `--no-direnv`; insert auto-allow block after `git worktree add` and before the existing "Worktree ready" message.
  - `pkgs/wt/completions/wt.bash` — add `--no-direnv` to `add` completion.
  - `pkgs/wt/completions/_wt` — add `--no-direnv` to `add` completion (zsh).
  - `pkgs/wt/completions/wt.fish` — add `--no-direnv` to `add` completion.
  - `pkgs/wt/completions/wt.nu` — add `--no-direnv` to `wt add` extern.
  - `pkgs/wt/README.md` — document the new default behavior, the opt-out flag, and the new test.

The four completion files change together every time a flag is added; they're decomposed by shell, not by responsibility, and that's the convention this codebase already settled on. Test lives next to its sibling under `pkgs/wt/tests/`.

---

## Task 1: Helpers + tests

Lay both helpers in `default.nix` *and* in the test file simultaneously (the test re-declares them — same convention as `test-upstream-gone.sh`, with a "keep in sync" comment). The test exercises the helpers in isolation; integration with `cmd_add` is Task 2.

**Files:**
- Create: `pkgs/wt/tests/test-add-direnv.sh`
- Modify: `pkgs/wt/default.nix` (add two helpers; do not yet wire into `cmd_add`)

- [ ] **Step 1: Write the test file**

Create `pkgs/wt/tests/test-add-direnv.sh` with this exact content:

```bash
#!/usr/bin/env bash
# Integration test for wt's direnv auto-allow helpers.
# Builds a fake worktree tree with .envrcs at multiple depths and asserts
# both helpers behave correctly. Stubs `direnv` via PATH so the test
# does not depend on the real binary.

set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

# Re-declare the helpers here so this test runs standalone without
# needing to parse bash out of a Nix string. Keep in sync with
# pkgs/wt/default.nix.

wt_find_envrcs() {
  local p="$1"
  find "$p" -name .envrc -not -path '*/.git/*' 2>/dev/null | sort | while IFS= read -r f; do
    printf '%s\n' "${f#$p/}"
  done
}

wt_allow_envrcs() {
  local p="$1" rel
  while IFS= read -r rel; do
    [ -z "$rel" ] && continue
    direnv allow "$p/$rel"
    echo "  allowed: $rel"
  done < <(wt_find_envrcs "$p")
}

tmp=$(mktemp -d)
stubdir=$(mktemp -d)
trap 'rm -rf "$tmp" "$stubdir"' EXIT

# Build a fake worktree mirroring the mlsa nested-envrc shape:
#   wt/.envrc
#   wt/infra/.envrc
#   wt/src/.envrc
mkdir -p "$tmp/wt/infra" "$tmp/wt/src"
echo 'use flake'             > "$tmp/wt/.envrc"
echo 'use flake ..#infra'    > "$tmp/wt/infra/.envrc"
echo 'source_up; layout node' > "$tmp/wt/src/.envrc"

# Test 1: wt_find_envrcs lists root + nested in sorted relative-path form.
expected=".envrc
infra/.envrc
src/.envrc"
actual=$(wt_find_envrcs "$tmp/wt")
[ "$actual" = "$expected" ] || fail "find_envrcs output: got '$actual' want '$expected'"
pass "wt_find_envrcs lists root + nested .envrcs as sorted relative paths"

# Test 2: wt_find_envrcs excludes .git/ subtree.
mkdir -p "$tmp/wt2/.git"
echo 'should-not-find' > "$tmp/wt2/.git/.envrc"
echo 'ok'              > "$tmp/wt2/.envrc"
actual=$(wt_find_envrcs "$tmp/wt2")
[ "$actual" = ".envrc" ] || fail "find_envrcs included .git/ entry: '$actual'"
pass "wt_find_envrcs excludes .git/ subtree"

# Test 3: wt_find_envrcs returns empty string when no .envrcs.
mkdir -p "$tmp/wt3"
actual=$(wt_find_envrcs "$tmp/wt3")
[ -z "$actual" ] || fail "find_envrcs on empty tree returned: '$actual'"
pass "wt_find_envrcs returns empty when no .envrcs"

# Test 4: wt_allow_envrcs calls a stubbed direnv with each absolute path.
cat > "$stubdir/direnv" <<EOF
#!/usr/bin/env bash
echo "DIRENV_CALLED \$*" >> "\$DIRENV_LOG"
EOF
chmod +x "$stubdir/direnv"

DIRENV_LOG="$tmp/direnv.log"
: > "$DIRENV_LOG"
out_file="$tmp/allow-out"
PATH="$stubdir:$PATH" DIRENV_LOG="$DIRENV_LOG" \
  wt_allow_envrcs "$tmp/wt" > "$out_file" 2>&1

grep -qxF "DIRENV_CALLED allow $tmp/wt/.envrc"        "$DIRENV_LOG" || fail "direnv not called for root .envrc"
grep -qxF "DIRENV_CALLED allow $tmp/wt/infra/.envrc"  "$DIRENV_LOG" || fail "direnv not called for infra/.envrc"
grep -qxF "DIRENV_CALLED allow $tmp/wt/src/.envrc"    "$DIRENV_LOG" || fail "direnv not called for src/.envrc"
[ "$(wc -l < "$DIRENV_LOG")" -eq 3 ] || fail "expected 3 direnv calls, got $(wc -l < "$DIRENV_LOG")"
pass "wt_allow_envrcs invokes direnv allow once per .envrc"

# Test 5: wt_allow_envrcs prints relative paths for each allowed file.
grep -qxF "  allowed: .envrc"        "$out_file" || fail "output missing 'allowed: .envrc'"
grep -qxF "  allowed: infra/.envrc"  "$out_file" || fail "output missing 'allowed: infra/.envrc'"
grep -qxF "  allowed: src/.envrc"    "$out_file" || fail "output missing 'allowed: src/.envrc'"
pass "wt_allow_envrcs prints relative paths for each allowed file"

echo "All direnv auto-allow checks passed."
```

- [ ] **Step 2: Run the test**

Run:
```
bash pkgs/wt/tests/test-add-direnv.sh
```

Expected output ends with `All direnv auto-allow checks passed.` and exits 0. The test passes against its own re-declared helpers — this step locks in the behavior we will implement in `default.nix`.

- [ ] **Step 3: Add the helpers to `default.nix`**

Open `pkgs/wt/default.nix`. Find the `upstream_gone()` helper (currently around line 47–55). Insert these two helpers immediately after `upstream_gone()`'s closing brace (around line 55), keeping a blank line above and below:

```nix
      wt_find_envrcs() {
        # $1 = path. Prints relative paths of all .envrc files, sorted.
        local p="$1"
        find "$p" -name .envrc -not -path '*/.git/*' 2>/dev/null | sort | while IFS= read -r f; do
          printf '%s\n' "''${f#$p/}"
        done
      }

      wt_allow_envrcs() {
        # $1 = worktree path. Calls `direnv allow` on each .envrc found.
        # Prints "  allowed: <relative>" per file. Caller is responsible for
        # the `command -v direnv` availability check.
        local p="$1" rel
        while IFS= read -r rel; do
          [ -z "$rel" ] && continue
          direnv allow "$p/$rel"
          echo "  allowed: $rel"
        done < <(wt_find_envrcs "$p")
      }
```

Note the `''${f#$p/}` Nix-string escape: the leading `''$` produces a literal `${...}` so Nix doesn't try to interpolate `f#$p/`. This matches the existing `''${1:-}` pattern in `cmd_add`.

- [ ] **Step 4: Build wt to verify the Nix source still parses**

Run:
```
nix build --no-link .#wt
```

Expected: exits 0 with no errors. (Build may produce no output if cached; that's fine — what matters is the exit code.)

- [ ] **Step 5: Diff helpers in test vs default.nix**

Sanity-check that the helper bodies are byte-identical to what the test re-declares. Run:
```
diff <(awk '/^wt_find_envrcs\(\) \{/,/^}/' pkgs/wt/tests/test-add-direnv.sh) \
     <(awk '/wt_find_envrcs\(\) \{/,/^      \}/' pkgs/wt/default.nix | sed 's/^      //')
```

Expected: empty diff (the awk + sed strips the Nix indentation; the body shape should match line-for-line). If diff shows differences, reconcile them now — drift here is exactly what the "keep in sync" comment is preventing.

- [ ] **Step 6: Run the test again**

```
bash pkgs/wt/tests/test-add-direnv.sh
```

Expected: same passing output as Step 2.

- [ ] **Step 7: Commit**

```
git add pkgs/wt/tests/test-add-direnv.sh pkgs/wt/default.nix
git commit -m "$(cat <<'EOF'
wt: add wt_find_envrcs / wt_allow_envrcs helpers

Helpers will be wired into cmd_add in a follow-up commit. Tested via
re-declaration in pkgs/wt/tests/test-add-direnv.sh, matching the
existing test-upstream-gone.sh pattern (helpers small enough to keep
in sync by hand; standalone test stays fast and dep-free).

Stubbed direnv on PATH lets the allow path run without requiring
direnv to be installed in the test environment.
EOF
)"
```

---

## Task 2: Wire auto-allow into `cmd_add` with `--no-direnv` flag

The helpers exist; now `cmd_add` parses the new flag, runs the auto-allow block when direnv is available and the flag isn't set, and emits a header naming the count.

**Files:**
- Modify: `pkgs/wt/default.nix:84–118` (`cmd_add` function body)

- [ ] **Step 1: Replace the head of `cmd_add` with flag-aware arg parsing**

In `pkgs/wt/default.nix`, find this block (the current opening of `cmd_add`, around line 84–88):

```nix
      cmd_add() {
        local branch="''${1:-}"
        if [ -z "$branch" ]; then
          echo "Usage: wt add <branch>" >&2
          exit 1
        fi
```

Replace with:

```nix
      cmd_add() {
        local branch=""
        local skip_direnv=false
        while [ $# -gt 0 ]; do
          case "$1" in
            --no-direnv) skip_direnv=true; shift ;;
            --) shift; break ;;
            -*) echo "Unknown flag: $1" >&2; exit 1 ;;
            *)
              if [ -z "$branch" ]; then
                branch="$1"; shift
              else
                echo "Unexpected argument: $1" >&2; exit 1
              fi
              ;;
          esac
        done

        if [ -z "$branch" ]; then
          echo "Usage: wt add [--no-direnv] <branch>" >&2
          exit 1
        fi
```

This preserves the existing branch-required behavior, adds `--no-direnv`, and rejects unknown `-*` flags up front.

- [ ] **Step 2: Insert the auto-allow block before the final "Worktree ready" message**

Still in `cmd_add`, find the existing block that prints "Worktree ready" (currently around line 115–117):

```nix
        echo ""
        echo "Worktree ready at: $WORKTREE_DIR/$branch"
        echo "  cd $wt_path"
      }
```

Replace with:

```nix
        if [ "$skip_direnv" != true ] && command -v direnv >/dev/null 2>&1; then
          local envrc_list
          envrc_list=$(wt_find_envrcs "$wt_path")
          if [ -n "$envrc_list" ]; then
            local n
            n=$(printf '%s\n' "$envrc_list" | wc -l)
            echo ""
            echo "Approving $n .envrc file(s) with direnv:"
            wt_allow_envrcs "$wt_path"
          fi
        fi

        echo ""
        echo "Worktree ready at: $WORKTREE_DIR/$branch"
        echo "  cd $wt_path"
      }
```

The auto-allow block runs unconditionally except for the two gates: `--no-direnv` flag, and `direnv` not on `PATH`. Empty worktrees (no `.envrc` files) skip the header silently.

- [ ] **Step 3: Build wt**

```
nix build --no-link .#wt
```

Expected: exits 0.

- [ ] **Step 4: Smoke test in the dotfiles repo**

This worktree (`wt-bootstrap-spec`) has its own `.envrc`. Use the just-built wt to add a throwaway worktree and verify the output:

```
WT=$(nix build --no-link --print-out-paths .#wt)/bin/wt
"$WT" add tmp-direnv-smoke
```

Expected output includes:
```
Creating new branch 'tmp-direnv-smoke'
Preparing worktree (new branch 'tmp-direnv-smoke')
HEAD is now at <sha> <commit-msg>

Approving 1 .envrc file(s) with direnv:
  allowed: .envrc

Worktree ready at: .worktrees/tmp-direnv-smoke
  cd /home/cmp/src/dotfiles/.worktrees/tmp-direnv-smoke
```

Then confirm direnv is allowed for the new worktree:
```
direnv status -c .worktrees/tmp-direnv-smoke
```

Expected: `Found RC allowed true` (or similar — the key is "allowed true", not "allowed false" or "not allowed").

- [ ] **Step 5: Smoke test the `--no-direnv` opt-out**

```
"$WT" rm tmp-direnv-smoke   # clean up first; answer prompts to delete branch too
"$WT" add tmp-no-direnv-smoke --no-direnv
```

Expected output: identical to current `wt add` (no "Approving" block). Confirm direnv is NOT allowed for the new worktree:
```
direnv status -c .worktrees/tmp-no-direnv-smoke
```

Expected: `Found RC allowed false` (or whatever direnv's "not allowed" wording is).

Clean up:
```
"$WT" rm tmp-no-direnv-smoke
```

- [ ] **Step 6: Commit**

```
git add pkgs/wt/default.nix
git commit -m "$(cat <<'EOF'
wt: wire direnv auto-allow into cmd_add (default on, --no-direnv opt-out)

After git worktree add, find every .envrc in the new tree (excluding
.git/) and run direnv allow on each. Skipped silently when direnv is
not on PATH or when --no-direnv is passed.

Default-on matches what the user does manually after every wt add
today and unblocks subagent workflows that fail silently when nested
.envrc chains aren't approved (mlsa src/.envrc + infra/.envrc is the
canonical case).
EOF
)"
```

---

## Task 3: Add `--no-direnv` to all four shell completions

**Files:**
- Modify: `pkgs/wt/completions/wt.bash`
- Modify: `pkgs/wt/completions/_wt`
- Modify: `pkgs/wt/completions/wt.fish`
- Modify: `pkgs/wt/completions/wt.nu`

- [ ] **Step 1: Update `pkgs/wt/completions/wt.bash`**

Replace the `add)` case (currently around lines 13–24):

```bash
    add)
      if [[ $COMP_CWORD -eq 2 ]]; then
        local branches
        branches=$(
          {
            git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null
            git for-each-ref --format='%(refname:lstrip=3)' refs/remotes 2>/dev/null
          } | grep -vE '^HEAD$' | sort -u
        )
        COMPREPLY=( $(compgen -W "$branches" -- "$cur") )
      fi
      ;;
```

with:

```bash
    add)
      if [[ "$cur" == --* ]]; then
        COMPREPLY=( $(compgen -W "--no-direnv" -- "$cur") )
      elif [[ $COMP_CWORD -eq 2 ]]; then
        local branches
        branches=$(
          {
            git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null
            git for-each-ref --format='%(refname:lstrip=3)' refs/remotes 2>/dev/null
          } | grep -vE '^HEAD$' | sort -u
        )
        COMPREPLY=( $(compgen -W "$branches" -- "$cur") )
      fi
      ;;
```

The `--*` branch wins when the user is typing a flag; otherwise positional branch completion still works at slot 2.

- [ ] **Step 2: Update `pkgs/wt/completions/_wt`**

Replace the `args` case body (currently lines 41–45):

```zsh
    args)
      case $words[1] in
        add) _wt_branches ;;
        rm)  _wt_worktrees ;;
      esac
      ;;
```

with:

```zsh
    args)
      case $words[1] in
        add)
          if [[ "$words[CURRENT]" == --* ]]; then
            _values 'flag' '--no-direnv[skip direnv allow on .envrc files]'
          else
            _wt_branches
          fi
          ;;
        rm)  _wt_worktrees ;;
      esac
      ;;
```

- [ ] **Step 3: Update `pkgs/wt/completions/wt.fish`**

Append at the end of the file (after the existing `add` arg completion at line 27):

```fish
complete -c wt -n '__fish_seen_subcommand_from add' -l no-direnv -d 'skip direnv allow on .envrc files'
```

- [ ] **Step 4: Update `pkgs/wt/completions/wt.nu`**

Replace the existing `wt add` extern (currently line 35):

```nu
export extern "wt add" [branch?: string@"nu-complete wt-branches"]
```

with:

```nu
export extern "wt add" [
  branch?: string@"nu-complete wt-branches"
  --no-direnv  # skip direnv allow on .envrc files
]
```

- [ ] **Step 5: Build wt to verify all completion files install correctly**

```
nix build --no-link .#wt
```

Expected: exits 0. (The build's `installShellCompletion` step runs the bash/zsh/fish completions through their respective syntax checks at install time; a syntax error in any of them fails the build.)

- [ ] **Step 6: Commit**

```
git add pkgs/wt/completions/
git commit -m "wt: complete --no-direnv flag for wt add across bash/zsh/fish/nu"
```

---

## Task 4: Update README and run final verification

**Files:**
- Modify: `pkgs/wt/README.md`

- [ ] **Step 1: Update README**

Replace the entire contents of `pkgs/wt/README.md` with:

````markdown
# wt

A thin wrapper around `git worktree` that keeps all worktrees under a
single `.worktrees/` directory at the repo root.

## Commands

- `wt init` — create `.worktrees/` and add it to `.git/info/exclude`
- `wt add [--no-direnv] <branch>` — create a worktree; checks out an
  existing branch or creates a new one off `HEAD`. By default, runs
  `direnv allow` on every `.envrc` found under the new worktree
  (excluding `.git/`), so the dev shell is activated for the worktree
  root and any nested sub-shell envrcs (e.g. monorepo `src/.envrc` +
  `infra/.envrc`). Pass `--no-direnv` to skip approval. If `direnv`
  is not on `PATH`, the approval step is silently skipped.
- `wt ls` — list active worktrees (passes through to `git worktree list`)
- `wt rm <branch>` — remove a worktree with prompts for uncommitted changes,
  an optional merge, and branch deletion. When the branch's upstream
  tracking ref is gone, recommends force delete (assumes squash-/rebase-merge)
- `wt help` — print usage

## Dependencies

- `git` — all worktree operations
- `coreutils` — basic shell utilities
- `direnv` (optional) — when present, `wt add` auto-allows discovered
  `.envrc` files. Missing `direnv` is not an error; the step is skipped.

Shell completions are installed for bash, zsh, fish, and nushell.

## Testing

Run the standalone behavior tests:

```
bash pkgs/wt/tests/test-upstream-gone.sh
bash pkgs/wt/tests/test-add-direnv.sh
```
````

- [ ] **Step 2: Smoke test in mlsa (the canonical nested-envrc case)**

This is a manual cross-repo verification — do it from the dotfiles worktree's just-built `wt`:

```
WT=$(nix build --no-link --print-out-paths .#wt)/bin/wt
cd ~/src/mlsa
"$WT" add tmp-mlsa-smoke
```

Expected output's "Approving N .envrc file(s)" line lists at least 3 files (root, `infra/`, `src/`):
```
Approving 3 .envrc file(s) with direnv:
  allowed: .envrc
  allowed: infra/.envrc
  allowed: src/.envrc
```

Confirm by `cd .worktrees/tmp-mlsa-smoke/infra && direnv status` (allowed: true) and same for `src/`.

Clean up:
```
cd ~/src/mlsa
"$WT" rm tmp-mlsa-smoke
cd ~/src/dotfiles/.worktrees/wt-bootstrap-spec
```

If mlsa's actual envrc layout differs from the spec's example (e.g., only one of `infra/` or `src/` exists), adjust expectations to match what `find -name .envrc` actually returns there. The point of the smoke test is "every `.envrc` that exists is allowed" — the count is incidental.

- [ ] **Step 3: Build the full home-manager config**

```
nix build --no-link .#homeConfigurations."cmp@$(hostname)".activationPackage
```

Expected: exits 0. Verifies the wt change doesn't break anything downstream.

- [ ] **Step 4: Commit**

```
git add pkgs/wt/README.md
git commit -m "$(cat <<'EOF'
wt: document direnv auto-allow behavior, --no-direnv flag, new test

README now lists direnv as an optional dependency, names the new
test, and documents the auto-allow default that wt add now applies
after creating a worktree.
EOF
)"
```

---

## Verification summary

After all tasks land, the following should be true:

- `bash pkgs/wt/tests/test-add-direnv.sh` exits 0 with five PASS lines.
- `bash pkgs/wt/tests/test-upstream-gone.sh` continues to exit 0 (regression check).
- `nix build .#wt` succeeds.
- `nix build .` (full home config) succeeds.
- `wt add foo` in dotfiles emits an "Approving N .envrc file(s)" line and `direnv status -c .worktrees/foo` shows `allowed true`.
- `wt add foo --no-direnv` does NOT emit the approving line and `direnv status` shows allowed false.
- `wt add foo` in mlsa allows root + `infra/.envrc` + `src/.envrc`.
- `wt add <TAB>` in zsh/bash/fish completes branch names; `wt add --<TAB>` completes `--no-direnv`.
- `PATH= "$WT" add tmp-no-direnv-binary` (PATH stripped so `command -v direnv` fails) creates the worktree, prints "Worktree ready", does NOT print the "Approving" header, and exits 0. `wt rm` cleans up.

---

## Notes for the implementer

- The two helpers are intentionally **not** called from anywhere except `cmd_add`. Keep them defined at the top of the script's `text` block (alongside `upstream_gone`) for discoverability; future work (the bootstrap-extras spec) will reuse `wt_find_envrcs` for `--json` output.
- Do not add a `command -v find` guard. `find` is in the `coreutils` runtime input; it's always present.
- Do not "improve" the test to use `nix build .#wt` and exec the real binary — the standalone-bash test convention is deliberate (fast, dep-free, no Nix evaluation in the test loop). If you need to verify the integrated `cmd_add` flow, do it manually per Task 2 Step 4–5 / Task 4 Step 2.
- If `direnv allow` itself fails (e.g., a malformed `.envrc`), the helper currently lets it bubble up — the loop continues to the next file but exit codes from `direnv` are not aggregated. This matches the spec's "let it fail loudly" call. Don't paper over it.
