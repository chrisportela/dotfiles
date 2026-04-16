# `wt` completions + squash-merge-aware cleanup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add zsh/bash/fish/nushell autocompletion to the `wt` worktree helper, and teach `wt rm` to recognize a `[gone]` upstream tracking branch as a squash-merge signal — explaining the assumption and flipping the force-delete prompt default.

**Architecture:** Keep `writeShellApplication` as the build primitive; wrap it with `.overrideAttrs` to add `installShellFiles` + `installShellCompletion` for bash/zsh/fish, plus a manual install of the nushell completion to `$out/share/nushell/vendor/autoload/wt.nu`. Add an `upstream_gone()` bash helper that reads `git for-each-ref --format='%(upstream:track)'` and looks for `[gone]`. Branch on that helper inside `cmd_rm`'s "not fully merged" path to pick the user-facing message and prompt default.

**Tech Stack:** Nix (writeShellApplication, installShellFiles), bash 5, zsh completion system, fish completion system, nushell `extern` declarations + custom completers, git plumbing (`for-each-ref`).

**Reference spec:** `docs/superpowers/specs/2026-04-16-wt-completions-squash-merge-design.md`.

---

## File Structure

- **Create:**
  - `pkgs/wt/completions/wt.bash` — bash completion
  - `pkgs/wt/completions/_wt` — zsh completion (underscore-prefix per zsh autoload convention)
  - `pkgs/wt/completions/wt.fish` — fish completion
  - `pkgs/wt/completions/wt.nu` — nushell completion
  - `pkgs/wt/README.md` — required by repo CLAUDE.md
  - `pkgs/wt/tests/test-upstream-gone.sh` — standalone integration test for `upstream_gone` + the `cmd_rm` force-delete branch selection
- **Modify:**
  - `pkgs/wt/default.nix` — add `installShellFiles` input; wrap the derivation with `.overrideAttrs` to install completions; add `upstream_gone()` helper; rework the "not fully merged" branch of `cmd_rm`
  - `modules/home/default.nix:48` — move `wt` out of the `stdenv.isLinux` conditional

Each completion file implements the same behavior (subcommand list, `add` → branches, `rm` → worktree dirs); they live together in `pkgs/wt/completions/` because they change together every time completion behavior changes. Tests live under `pkgs/wt/tests/` for the same reason.

---

## Task 1: Completion install scaffolding + README

Lay the Nix plumbing before writing completion content. Creates the directory layout and stub files; builds will succeed with empty-but-valid completion scripts.

**Files:**
- Create: `pkgs/wt/README.md`
- Create: `pkgs/wt/completions/wt.bash` (stub)
- Create: `pkgs/wt/completions/_wt` (stub)
- Create: `pkgs/wt/completions/wt.fish` (stub)
- Create: `pkgs/wt/completions/wt.nu` (stub)
- Modify: `pkgs/wt/default.nix`

- [ ] **Step 1: Write `pkgs/wt/README.md`**

```markdown
# wt

A thin wrapper around `git worktree` that keeps all worktrees under a
single `.worktrees/` directory at the repo root.

## Commands

- `wt init` — create `.worktrees/` and add it to `.git/info/exclude`
- `wt add <branch>` — create a worktree; checks out an existing branch or
  creates a new one off `HEAD`
- `wt ls` — list active worktrees (passes through to `git worktree list`)
- `wt rm <branch>` — remove a worktree with prompts for uncommitted changes,
  an optional merge, and branch deletion. When the branch's upstream
  tracking ref is gone, recommends force delete (assumes squash-/rebase-merge)
- `wt help` — print usage

## Dependencies

- `git` — all worktree operations
- `coreutils` — basic shell utilities

Shell completions are installed for bash, zsh, fish, and nushell.

## Testing

Run the upstream-gone behavior test standalone:

```
bash pkgs/wt/tests/test-upstream-gone.sh
```
```

- [ ] **Step 2: Create stub completion files**

Each file gets a one-line comment so it's valid syntax in its respective shell. They will be filled in by later tasks.

`pkgs/wt/completions/wt.bash`:

```bash
# wt(1) bash completion — populated in Task 2
```

`pkgs/wt/completions/_wt`:

```zsh
#compdef wt
# wt(1) zsh completion — populated in Task 3
```

`pkgs/wt/completions/wt.fish`:

```fish
# wt(1) fish completion — populated in Task 4
```

`pkgs/wt/completions/wt.nu`:

```nu
# wt(1) nushell completion — populated in Task 5
```

- [ ] **Step 3: Rewrite `pkgs/wt/default.nix` to install completions**

Full replacement — adds `installShellFiles`, wraps the `writeShellApplication` result with `.overrideAttrs`, and adds a `postInstall` that installs all four completions. Note the source text is identical to today; that gets edited in Task 6.

```nix
{
  writeShellApplication,
  git,
  coreutils,
  installShellFiles,
  lib,
}:

let
  wt = writeShellApplication {
    name = "wt";

    runtimeInputs = [
      git
      coreutils
    ];

    meta = with lib; {
      platforms = platforms.unix ++ platforms.darwin;
    };

    text = ''
      WORKTREE_DIR=".worktrees"

      usage() {
        echo "Usage: wt <command> [args]"
        echo ""
        echo "Commands:"
        echo "  init          Setup .worktrees/ and add to .git/info/exclude"
        echo "  add <branch>  Create a worktree with a new or existing branch"
        echo "  ls            List active worktrees"
        echo "  rm <branch>   Remove a worktree interactively"
        echo "  help          Show this help message"
      }

      ensure_git_repo() {
        if ! git rev-parse --show-toplevel &>/dev/null; then
          echo "Error: Not in a git repository" >&2
          exit 1
        fi
      }

      get_root() {
        git rev-parse --show-toplevel
      }

      cmd_init() {
        ensure_git_repo
        local root
        root="$(get_root)"
        local wt_path="$root/$WORKTREE_DIR"

        # Create .worktrees directory
        if [ -d "$wt_path" ]; then
          echo ".worktrees/ already exists"
        else
          mkdir -p "$wt_path"
          echo "Created .worktrees/"
        fi

        # Add to .git/info/exclude
        local exclude="$root/.git/info/exclude"
        mkdir -p "$root/.git/info"
        touch "$exclude"

        if ! grep -q "^\.worktrees/?$\|^\.worktrees$" "$exclude" 2>/dev/null; then
          echo ".worktrees/" >> "$exclude"
          echo "Added .worktrees/ to .git/info/exclude"
        else
          echo ".worktrees/ already in .git/info/exclude"
        fi
      }

      cmd_add() {
        local branch="''${1:-}"
        if [ -z "$branch" ]; then
          echo "Usage: wt add <branch>" >&2
          exit 1
        fi

        ensure_git_repo
        local root
        root="$(get_root)"
        local wt_path="$root/$WORKTREE_DIR/$branch"

        # Auto-init if needed
        if [ ! -d "$root/$WORKTREE_DIR" ]; then
          cmd_init
        fi

        if [ -d "$wt_path" ]; then
          echo "Error: Worktree already exists at $WORKTREE_DIR/$branch" >&2
          exit 1
        fi

        # Check if branch already exists
        if git show-ref --verify --quiet "refs/heads/$branch"; then
          echo "Checking out existing branch '$branch'"
          git worktree add "$wt_path" "$branch"
        else
          echo "Creating new branch '$branch'"
          git worktree add -b "$branch" "$wt_path"
        fi

        echo ""
        echo "Worktree ready at: $WORKTREE_DIR/$branch"
        echo "  cd $wt_path"
      }

      cmd_ls() {
        ensure_git_repo
        git worktree list
      }

      cmd_rm() {
        local branch="''${1:-}"
        if [ -z "$branch" ]; then
          echo "Usage: wt rm <branch>" >&2
          exit 1
        fi

        ensure_git_repo
        local root
        root="$(get_root)"
        local wt_path="$root/$WORKTREE_DIR/$branch"

        if [ ! -d "$wt_path" ]; then
          echo "Error: No worktree at $WORKTREE_DIR/$branch" >&2
          exit 1
        fi

        # Check for uncommitted/untracked files
        local dirty_files
        dirty_files="$(git -C "$wt_path" status --porcelain 2>/dev/null || true)"

        local force_remove=false
        if [ -n "$dirty_files" ]; then
          echo "Worktree has uncommitted/untracked files:"
          echo "$dirty_files"
          echo ""
          read -r -p "Force remove worktree? [y/N] " answer
          if [[ "$answer" =~ ^[Yy]$ ]]; then
            force_remove=true
          else
            echo "Aborted."
            exit 0
          fi
        fi

        # Remove the worktree
        if [ "$force_remove" = true ]; then
          git worktree remove --force "$wt_path"
        else
          git worktree remove "$wt_path"
        fi
        echo "Removed worktree at $WORKTREE_DIR/$branch"

        # Check if branch exists before asking about it
        if ! git show-ref --verify --quiet "refs/heads/$branch"; then
          echo "Branch '$branch' does not exist (may have been removed already)."
          return
        fi

        # Ask about merging
        local merged=false
        read -r -p "Merge branch '$branch' into current branch? [y/N] " answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
          if git merge "$branch"; then
            merged=true
            echo "Merged '$branch' into $(git branch --show-current)"
          else
            echo "Merge failed — resolve conflicts manually." >&2
            return
          fi
        fi

        # Ask about deleting the branch
        read -r -p "Delete branch '$branch'? [Y/n] " answer
        if [[ "''${answer:-Y}" =~ ^[Nn]$ ]]; then
          echo "Keeping branch '$branch'."
          return
        fi

        # Try normal delete first
        if git branch -d "$branch" 2>/dev/null; then
          echo "Deleted branch '$branch'."
        else
          # Branch not fully merged
          if [ "$merged" = false ]; then
            echo "Branch '$branch' is not fully merged."
            read -r -p "Force delete branch? [y/N] " answer
            if [[ "$answer" =~ ^[Yy]$ ]]; then
              git branch -D "$branch"
              echo "Force deleted branch '$branch'."
            else
              echo "Keeping branch '$branch'."
            fi
          fi
        fi
      }

      # Main dispatch
      command="''${1:-help}"
      shift || true

      case "$command" in
        init) cmd_init "$@" ;;
        add)  cmd_add "$@" ;;
        ls)   cmd_ls "$@" ;;
        rm)   cmd_rm "$@" ;;
        help) usage ;;
        *)
          echo "Unknown command: $command" >&2
          usage >&2
          exit 1
          ;;
      esac
    '';
  };
in
wt.overrideAttrs (old: {
  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ installShellFiles ];
  postInstall = (old.postInstall or "") + ''
    installShellCompletion --cmd wt \
      --bash ${./completions/wt.bash} \
      --zsh  ${./completions/_wt} \
      --fish ${./completions/wt.fish}
    install -Dm644 ${./completions/wt.nu} \
      $out/share/nushell/vendor/autoload/wt.nu
  '';
})
```

- [ ] **Step 4: Stage new files so Nix can see them**

```bash
git add pkgs/wt/README.md pkgs/wt/completions/ pkgs/wt/default.nix
```

Flake evaluation cannot see untracked files (see repo CLAUDE.md).

- [ ] **Step 5: Build and verify completions are installed**

```bash
cd /home/cmp/src/dotfiles
nix build .#wt
```

Expected: build succeeds. Then:

```bash
ls -la result/share/bash-completion/completions/
ls -la result/share/zsh/site-functions/
ls -la result/share/fish/vendor_completions.d/
ls -la result/share/nushell/vendor/autoload/
```

Expected output should include `wt` (bash), `_wt` (zsh), `wt.fish` (fish), `wt.nu` (nushell).

- [ ] **Step 6: Commit**

```bash
git add pkgs/wt/
git commit -m "feat(wt): scaffold shell completion install

Add README, empty completion stubs, and wire installShellFiles into
the wt derivation via overrideAttrs. Completion content follows in
separate commits."
```

---

## Task 2: Bash completion

**Files:**
- Modify: `pkgs/wt/completions/wt.bash`

- [ ] **Step 1: Replace the stub with the full completion script**

```bash
# wt(1) bash completion
_wt() {
  local cur subcmd
  cur="${COMP_WORDS[COMP_CWORD]}"
  subcmd="${COMP_WORDS[1]:-}"

  if [[ $COMP_CWORD -eq 1 ]]; then
    COMPREPLY=( $(compgen -W "init add ls rm help" -- "$cur") )
    return
  fi

  case "$subcmd" in
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
    rm)
      if [[ $COMP_CWORD -eq 2 ]]; then
        local root wts
        root=$(git rev-parse --show-toplevel 2>/dev/null) || return
        if [[ -d "$root/.worktrees" ]]; then
          wts=$(command ls -1 "$root/.worktrees" 2>/dev/null)
          COMPREPLY=( $(compgen -W "$wts" -- "$cur") )
        fi
      fi
      ;;
  esac
}
complete -F _wt wt
```

Key choices:
- Two separate `for-each-ref` invocations: local uses `%(refname:short)` (e.g., `feature/foo`), remote uses `%(refname:lstrip=3)` which strips `refs/remotes/<remote>/` cleanly (a single `sed 's|^[^/]+/||'` would incorrectly mangle local branches like `feature/foo`).
- `compgen -W` with space-separated string works because branch/worktree names can't contain spaces in git.
- No reliance on `bash-completion`'s `_init_completion` — keeps it working in environments where that library isn't loaded.

- [ ] **Step 2: Syntax-check**

```bash
bash -n pkgs/wt/completions/wt.bash
```

Expected: no output (clean parse).

- [ ] **Step 3: Smoke-test the completion function**

```bash
bash -c '
  source pkgs/wt/completions/wt.bash
  COMP_WORDS=(wt ""); COMP_CWORD=1
  _wt
  echo "subcommands: ${COMPREPLY[*]}"

  COMP_WORDS=(wt add ""); COMP_CWORD=2
  _wt
  echo "add candidates count: ${#COMPREPLY[@]}"
'
```

Expected: `subcommands: init add ls rm help`, and a non-zero `add candidates count` (the dotfiles repo has many branches).

- [ ] **Step 4: Build to ensure the installed copy is current**

```bash
nix build .#wt && ls -la result/share/bash-completion/completions/wt
```

Expected: symlink to the updated file in the Nix store.

- [ ] **Step 5: Commit**

```bash
git add pkgs/wt/completions/wt.bash
git commit -m "feat(wt): bash completion for subcommands and positional args"
```

---

## Task 3: Zsh completion

**Files:**
- Modify: `pkgs/wt/completions/_wt`

- [ ] **Step 1: Replace the stub with the full completion**

```zsh
#compdef wt

_wt_branches() {
  local -a branches
  branches=(
    ${(@f)"$(git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null)"}
    ${(@f)"$(git for-each-ref --format='%(refname:lstrip=3)' refs/remotes 2>/dev/null)"}
  )
  # Drop 'HEAD' entries (from refs/remotes/<remote>/HEAD)
  branches=(${branches:#HEAD})
  _describe 'branch' branches
}

_wt_worktrees() {
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return
  [[ -d "$root/.worktrees" ]] || return
  local -a wts
  wts=("$root/.worktrees"/*(/N:t))
  (( ${#wts} )) || return
  _describe 'worktree' wts
}

_wt() {
  local state

  _arguments -C \
    '1: :->command' \
    '*:: :->args'

  case $state in
    command)
      _values 'subcommand' \
        'init[setup .worktrees and exclude]' \
        'add[create a worktree]' \
        'ls[list active worktrees]' \
        'rm[remove a worktree]' \
        'help[show help]'
      ;;
    args)
      case $words[1] in
        add) _wt_branches ;;
        rm)  _wt_worktrees ;;
      esac
      ;;
  esac
}

_wt "$@"
```

Key choices:
- `${(@f)...}` splits command output on newlines into an array, preserving every branch name even with odd characters.
- Glob qualifier `(/N:t)` on the worktrees glob: `/` = only directories, `N` = null glob (no match is OK), `:t` = tail (basename).
- `_describe` integrates with zsh's grouping/description system.

- [ ] **Step 2: Syntax-check**

```bash
zsh -n pkgs/wt/completions/_wt
```

Expected: no output.

- [ ] **Step 3: Smoke-test**

```bash
zsh -c '
  autoload -Uz compinit && compinit -u
  fpath=($PWD/pkgs/wt/completions $fpath)
  autoload -Uz _wt
  # Trigger completion and capture what _values would offer
  print -rl -- $(
    _wt() { _values subcommand init add ls rm help }
    _wt
    print -r -- "${reply[@]:-subcommands emitted}"
  )
' 2>&1 | head -20
```

Expected: no errors. The zsh completion system is harder to smoke-test without an interactive shell, so this step just confirms loading doesn't blow up.

- [ ] **Step 4: Build**

```bash
nix build .#wt && ls -la result/share/zsh/site-functions/_wt
```

- [ ] **Step 5: Commit**

```bash
git add pkgs/wt/completions/_wt
git commit -m "feat(wt): zsh completion with branch and worktree dynamic args"
```

---

## Task 4: Fish completion

**Files:**
- Modify: `pkgs/wt/completions/wt.fish`

- [ ] **Step 1: Replace the stub with the full completion**

```fish
function __wt_branches
    git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null
    git for-each-ref --format='%(refname:lstrip=3)' refs/remotes 2>/dev/null
end

function __wt_worktrees
    set -l root (git rev-parse --show-toplevel 2>/dev/null)
    or return
    if test -d "$root/.worktrees"
        for d in $root/.worktrees/*/
            basename $d
        end
    end
end

# Disable file completion by default; subcommand-specific rules re-enable dynamic args.
complete -c wt -f

# Subcommands (only when no subcommand chosen yet)
complete -c wt -n __fish_use_subcommand -a init -d 'setup .worktrees and exclude'
complete -c wt -n __fish_use_subcommand -a add  -d 'create a worktree'
complete -c wt -n __fish_use_subcommand -a ls   -d 'list active worktrees'
complete -c wt -n __fish_use_subcommand -a rm   -d 'remove a worktree'
complete -c wt -n __fish_use_subcommand -a help -d 'show help'

# Args
complete -c wt -n '__fish_seen_subcommand_from add' -a '(__wt_branches)'
complete -c wt -n '__fish_seen_subcommand_from rm'  -a '(__wt_worktrees)'
```

- [ ] **Step 2: Syntax check (if `fish` is available)**

```bash
if command -v fish >/dev/null; then
  fish --no-execute pkgs/wt/completions/wt.fish
  echo "fish parse: OK"
else
  echo "fish not installed locally; skipping fish -n"
fi
```

Expected: "fish parse: OK" or the skip message. No fish dependency is introduced by the build — the completion is consumed by fish users, not checked by Nix.

- [ ] **Step 3: Build**

```bash
nix build .#wt && ls -la result/share/fish/vendor_completions.d/wt.fish
```

- [ ] **Step 4: Commit**

```bash
git add pkgs/wt/completions/wt.fish
git commit -m "feat(wt): fish completion for subcommands, branches, worktrees"
```

---

## Task 5: Nushell completion

**Files:**
- Modify: `pkgs/wt/completions/wt.nu`

- [ ] **Step 1: Replace the stub with the full completion**

```nu
# wt(1) nushell completion

def "nu-complete wt-subcommand" [] {
  [
    { value: "init", description: "setup .worktrees and exclude" }
    { value: "add",  description: "create a worktree" }
    { value: "ls",   description: "list active worktrees" }
    { value: "rm",   description: "remove a worktree" }
    { value: "help", description: "show help" }
  ]
}

def "nu-complete wt-branches" [] {
  let local_refs = (do -i { git for-each-ref --format='%(refname:short)' refs/heads } | lines)
  let remote_refs = (do -i { git for-each-ref --format='%(refname:lstrip=3)' refs/remotes } | lines)
  $local_refs | append $remote_refs | where $it != "HEAD" | uniq
}

def "nu-complete wt-worktrees" [] {
  let root = (do -i { git rev-parse --show-toplevel } | str trim)
  if ($root | is-empty) { return [] }
  let wtdir = $"($root)/.worktrees"
  if not ($wtdir | path exists) { return [] }
  ls $wtdir | where type == dir | get name | path basename
}

# Top-level dispatch so `wt <TAB>` offers subcommands
export extern "wt" [
  command?: string@"nu-complete wt-subcommand"
  ...args: string
]

# Per-subcommand externs for positional arg completion
export extern "wt init" []
export extern "wt add" [branch?: string@"nu-complete wt-branches"]
export extern "wt ls" []
export extern "wt rm" [branch?: string@"nu-complete wt-worktrees"]
export extern "wt help" []
```

Key choices:
- `do -i { ... }` ignores errors (nushell treats non-zero exit as an error by default) so completion doesn't blow up outside a git repo.
- Both top-level `wt` extern and per-subcommand externs: the top-level one provides `wt <TAB>` subcommand completion; the per-subcommand externs provide positional completion for `wt add <TAB>` and `wt rm <TAB>`.
- Nushell loads any `.nu` file in `$nu.vendor-autoload-dirs` at startup; the `$out/share/nushell/vendor/autoload/wt.nu` install path (from Task 1) lands in the right place given home-manager's default `XDG_DATA_DIRS`.

- [ ] **Step 2: Syntax check (if `nu` is available)**

```bash
if command -v nu >/dev/null; then
  nu --ide-check 0 pkgs/wt/completions/wt.nu
  echo "nu parse: exit=$?"
else
  echo "nushell not installed locally; skipping nu --ide-check"
fi
```

`nu --ide-check` returns JSON diagnostics; non-zero exit is the failure signal. Expect exit 0.

- [ ] **Step 3: Build and verify install path**

```bash
nix build .#wt
test -f result/share/nushell/vendor/autoload/wt.nu && echo "nu completion installed: OK"
```

Expected: "nu completion installed: OK".

- [ ] **Step 4: Commit**

```bash
git add pkgs/wt/completions/wt.nu
git commit -m "feat(wt): nushell completion via extern declarations"
```

---

## Task 6: `upstream_gone` helper + integration test

This is the one piece of non-trivial new logic. Write the test first so it fails, then add the helper, then confirm it passes.

**Files:**
- Create: `pkgs/wt/tests/test-upstream-gone.sh`
- Modify: `pkgs/wt/default.nix`

- [ ] **Step 1: Write the test script**

`pkgs/wt/tests/test-upstream-gone.sh`:

```bash
#!/usr/bin/env bash
# Integration test for wt's upstream_gone() helper.
# Builds a real temp git repo with four branch states and asserts the
# helper's return value for each.

set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

# Re-declare the helper here so this test runs standalone without
# needing to parse bash out of a Nix string. Keep in sync with
# pkgs/wt/default.nix.
upstream_gone() {
  local track
  track=$(git for-each-ref --format='%(upstream:track)' "refs/heads/$1")
  [[ "$track" == *"[gone]"* ]]
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Bare "remote" + a working clone
git init --quiet --bare "$tmp/remote.git"
git clone --quiet "$tmp/remote.git" "$tmp/repo"
cd "$tmp/repo"
git config user.email test@example.com
git config user.name test

# Initial commit on main
echo hi > README
git add README
git commit --quiet -m init
git push --quiet -u origin HEAD:main

# Case 1: branch with [gone] upstream (was pushed, then remote branch deleted)
git checkout --quiet -b gone-branch
echo x > x; git add x; git commit --quiet -m x
git push --quiet -u origin gone-branch
git push --quiet origin --delete gone-branch
git fetch --quiet --prune

# Case 2: branch with a valid upstream
git checkout --quiet -b alive-branch main
echo y > y; git add y; git commit --quiet -m y
git push --quiet -u origin alive-branch

# Case 3: local-only branch, never pushed
git checkout --quiet -b local-only main

# Case 4: a branch name that does not exist at all
# (upstream_gone on a nonexistent branch returns empty -> non-match -> false)

# Assertions
if upstream_gone gone-branch; then
  pass "gone-branch -> upstream_gone returns 0"
else
  fail "gone-branch should report upstream gone"
fi

if upstream_gone alive-branch; then
  fail "alive-branch should NOT report upstream gone"
else
  pass "alive-branch -> upstream_gone returns non-zero"
fi

if upstream_gone local-only; then
  fail "local-only (never pushed) should NOT report upstream gone"
else
  pass "local-only -> upstream_gone returns non-zero"
fi

if upstream_gone does-not-exist; then
  fail "nonexistent branch should NOT report upstream gone"
else
  pass "does-not-exist -> upstream_gone returns non-zero"
fi

echo "All upstream_gone checks passed."
```

- [ ] **Step 2: Make it executable and run — expect PASS**

```bash
chmod +x pkgs/wt/tests/test-upstream-gone.sh
bash pkgs/wt/tests/test-upstream-gone.sh
```

Expected: four `PASS:` lines followed by `All upstream_gone checks passed.` exit 0.

Why this passes before we touch `default.nix`: the helper is defined inside the test script for isolation. The test is checking the **logic**, not the Nix packaging. Tasks 7 below actually wires it into `cmd_rm`.

- [ ] **Step 3: Add the helper to `pkgs/wt/default.nix`**

Insert after `get_root()` (around line 44 of the current file, inside the `text = ''`…`'';` block). The `\[gone\]` is a literal bracket pattern for bash; no escaping needed for Nix because it's inside a `''` string that only escapes `''` and `$`.

```bash
      upstream_gone() {
        # $1 = branch name
        # Returns 0 iff the branch has an upstream tracking ref that is now gone.
        # This is the typical state after a GitHub squash-/rebase-merge where
        # the PR branch was auto-deleted on the remote.
        local track
        track=$(git for-each-ref --format='%(upstream:track)' "refs/heads/$1")
        [[ "$track" == *"[gone]"* ]]
      }
```

Exact location: place between the closing `}` of `get_root()` and the opening of `cmd_init()`.

- [ ] **Step 4: Build and verify the helper is present**

```bash
nix build .#wt
grep -c upstream_gone result/bin/wt
```

Expected: a positive count (the function definition lives in the installed script).

- [ ] **Step 5: Commit**

```bash
git add pkgs/wt/default.nix pkgs/wt/tests/test-upstream-gone.sh
git commit -m "feat(wt): add upstream_gone helper + integration test

Detects branches whose upstream tracking ref shows [gone] — the
typical state after a GitHub squash- or rebase-merge with remote
branch auto-deletion."
```

---

## Task 7: Rewire `cmd_rm` force-delete flow

Use the new helper to pick between the recommended (default-Yes) prompt and the original (default-No) prompt.

**Files:**
- Modify: `pkgs/wt/default.nix` — the tail of `cmd_rm`

- [ ] **Step 1: Replace the force-delete block in `cmd_rm`**

Replace the current (post–Task 6) block:

```bash
        # Try normal delete first
        if git branch -d "$branch" 2>/dev/null; then
          echo "Deleted branch '$branch'."
        else
          # Branch not fully merged
          if [ "$merged" = false ]; then
            echo "Branch '$branch' is not fully merged."
            read -r -p "Force delete branch? [y/N] " answer
            if [[ "$answer" =~ ^[Yy]$ ]]; then
              git branch -D "$branch"
              echo "Force deleted branch '$branch'."
            else
              echo "Keeping branch '$branch'."
            fi
          fi
        fi
```

…with:

```bash
        # Try normal delete first
        if git branch -d "$branch" 2>/dev/null; then
          echo "Deleted branch '$branch'."
        else
          # Branch not fully merged
          if [ "$merged" = false ]; then
            if upstream_gone "$branch"; then
              echo "Branch '$branch' is not fully merged locally, but its upstream"
              echo "tracking branch is gone. This usually means it was squash- or"
              echo "rebase-merged on the remote and then deleted (common on GitHub"
              echo "PR merge). Recommending force delete."
              read -r -p "Force delete branch? [Y/n] " answer
              if [[ "''${answer:-Y}" =~ ^[Nn]$ ]]; then
                echo "Keeping branch '$branch'."
              else
                git branch -D "$branch"
                echo "Force deleted branch '$branch'."
              fi
            else
              echo "Branch '$branch' is not fully merged."
              read -r -p "Force delete branch? [y/N] " answer
              if [[ "$answer" =~ ^[Yy]$ ]]; then
                git branch -D "$branch"
                echo "Force deleted branch '$branch'."
              else
                echo "Keeping branch '$branch'."
              fi
            fi
          fi
        fi
```

- [ ] **Step 2: Build**

```bash
nix build .#wt
```

Expected: success.

- [ ] **Step 3: Manual smoke test — `[gone]` path**

```bash
# In a scratch directory:
tmp=$(mktemp -d) && cd "$tmp"
git init --bare remote.git
git clone remote.git repo
cd repo
git config user.email test@example.com
git config user.name test
echo hi > README && git add README && git commit -qm init
git push -qu origin HEAD:main

# Create the "squash-merged" branch state
git checkout -qb feature
echo x > x && git add x && git commit -qm x
git push -qu origin feature
git push -q origin --delete feature
git fetch -q --prune

# Make it a wt-managed worktree
mkdir -p .worktrees
git worktree add .worktrees/feature feature

# Now test — answer the prompts with the defaults (just press Enter)
printf '\n\n\n' | "$OLDPWD/result/bin/wt" rm feature
```

Expected output includes: "Branch 'feature' is not fully merged locally, but its upstream tracking branch is gone." followed by the `[Y/n]` prompt, and (after defaulting to Yes) `Force deleted branch 'feature'.`

- [ ] **Step 4: Manual smoke test — non-`[gone]` path (unchanged old behavior)**

```bash
# From the same repo:
cd "$OLDPWD"  # back to the wt repo with the built result/
# Create a branch with uncommitted upstream-less commits
tmp2=$(mktemp -d) && cd "$tmp2"
git init -q
git config user.email test@example.com
git config user.name test
echo a > a && git add a && git commit -qm a
git checkout -qb side
echo b > b && git add b && git commit -qm b
git checkout -q master 2>/dev/null || git checkout -q main
mkdir -p .worktrees
git worktree add .worktrees/side side

# rm with Enter-Enter-Enter to accept defaults (don't merge, don't keep branch, don't force-delete)
printf '\n\n\n' | "$OLDPWD/result/bin/wt" rm side
```

Expected: "Branch 'side' is not fully merged." followed by `[y/N]` prompt defaulting to No, final message "Keeping branch 'side'."

- [ ] **Step 5: Commit**

```bash
git add pkgs/wt/default.nix
git commit -m "feat(wt): recommend force delete when upstream is gone

When git branch -d fails as 'not fully merged', check whether the
branch's upstream tracking ref is [gone]. If it is, explain that the
remote branch was likely squash-/rebase-merged and deleted, and flip
the force-delete prompt default to Yes. Non-[gone] paths retain the
original safe default of No."
```

---

## Task 8: Remove Linux-only guard in home module

The `stdenv.isLinux` guard was a workaround for the nixpkgs `Wt` C++ toolkit shadowing the package — fixed in commit `dfbd70d`. Verified by the user.

**Files:**
- Modify: `modules/home/default.nix:48`

- [ ] **Step 1: Inline `wt` into the platform-agnostic list**

Change:

```nix
        [
          curl
          doggo
          # ... other platform-agnostic packages ...
          setup-envrc
        ]
        ++ lib.optionals stdenv.isLinux [ wt ]
```

To:

```nix
        [
          curl
          doggo
          # ... other platform-agnostic packages ...
          setup-envrc
          wt
        ]
```

(Remove the `++ lib.optionals stdenv.isLinux [ wt ]` line entirely, append `wt` to the main list in alphabetical-ish order near `setup-envrc`.)

- [ ] **Step 2: Build the full home-manager config locally**

```bash
nix build .
```

Expected: success on the current host.

- [ ] **Step 3: If on Linux, also build Darwin config (cross-eval check)**

```bash
nix build .#darwinConfigurations.roxy.system --dry-run
```

Expected: eval succeeds (no platform errors). `--dry-run` avoids needing a Darwin builder.

If on Darwin, mirror with:

```bash
nix build .#nixosConfigurations.ada.config.system.build.toplevel --dry-run
```

- [ ] **Step 4: Commit**

```bash
git add modules/home/default.nix
git commit -m "feat(home): make wt available on all platforms

The Linux-only guard was a workaround for the nixpkgs Wt C++ toolkit
shadowing the package name. That issue was resolved in dfbd70d, so wt
can join the cross-platform package list."
```

---

## Task 9: Final verification

**No files modified** — this task only runs checks against everything built so far.

- [ ] **Step 1: Full build**

```bash
nix build .#wt
nix build .
```

Both must succeed.

- [ ] **Step 2: Re-run the upstream_gone integration test**

```bash
bash pkgs/wt/tests/test-upstream-gone.sh
```

Expected: four `PASS:` lines.

- [ ] **Step 3: Verify all completion artifacts**

```bash
for f in \
  result/bin/wt \
  result/share/bash-completion/completions/wt \
  result/share/zsh/site-functions/_wt \
  result/share/fish/vendor_completions.d/wt.fish \
  result/share/nushell/vendor/autoload/wt.nu
do
  test -e "$f" && echo "OK  $f" || echo "MISS $f"
done
```

Expected: five `OK` lines.

- [ ] **Step 4: Confirm cmd_rm force-delete branch contains the new text**

```bash
grep -c "squash- or" result/bin/wt
```

Expected: `1`.

- [ ] **Step 5: Open a PR (optional)**

If the user asks for a PR, use the `commit-commands:commit-push-pr` skill. Otherwise stop here; the branch is ready.

---

## Self-review (against the spec)

- **Goals:**
  - "Ship autocompletion for zsh, bash, fish, and nushell" — Tasks 1-5. ✓
  - "In `wt rm`, detect `[gone]` upstream, explain the assumption, flip the prompt default" — Tasks 6 and 7. ✓
  - "Keep the package shape (`writeShellApplication`)" — Task 1 uses `.overrideAttrs`, preserves the original derivation. ✓

- **Non-goals:** no task touches `git cherry`, no task adds an implicit `git fetch`, no task implements the DF-10 scaffolding. ✓

- **Files touched in spec §6 vs plan:** all six files from the spec appear in the plan (`default.nix`, four completion files, README, module). Plan adds `pkgs/wt/tests/test-upstream-gone.sh` as a test artifact (not in spec §6, but aligns with the spec's Verification section asking for the squash-merge-flow test). ✓

- **Verification coverage:** every manual test listed in the spec's Verification section has a corresponding step — `nix build .#wt`, full `nix build .`, smoke tests per shell (Tasks 2-5), `[gone]` path manual test (Task 7 step 3), non-`[gone]` path (Task 7 step 4), never-pushed branch case (Task 6 test script covers this). ✓

- **Placeholder scan:** no TBD/TODO/"implement later"/"similar to Task N"/unnamed helpers. Every step shows the exact code or command. ✓

- **Type/name consistency:** `upstream_gone` used with the same signature (`$1 = branch name`) in Task 6 (helper + test) and Task 7 (caller). Completion function names (`_wt_branches`, `_wt_worktrees`, `__wt_branches`, `__wt_worktrees`, `nu-complete wt-branches`, `nu-complete wt-worktrees`) vary by shell convention but are internally consistent within each script. ✓
