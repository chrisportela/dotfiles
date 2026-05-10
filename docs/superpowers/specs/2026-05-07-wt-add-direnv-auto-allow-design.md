# `wt add` direnv auto-allow — design

**Date:** 2026-05-07
**Target package:** `pkgs/wt/`
**Status:** Draft, pending review
**Predecessor:** [2026-04-16-wt-completions-squash-merge-design.md](./2026-04-16-wt-completions-squash-merge-design.md) — explicitly deferred this work as part of "DF-10".
**Companion (deferred):** [2026-05-07-wt-add-bootstrap-extras-design.md](./2026-05-07-wt-add-bootstrap-extras-design.md) — copy patterns, hooks, JSON output, per-repo config. Builds on this MVP.

## Problem

After `wt add <branch>`, every `.envrc` in the new worktree is unapproved. Until the user runs `direnv allow` on each one, the worktree's tools resolve from the global `PATH` instead of the project's dev shell — silently. The failure mode is "commands run, but they're the wrong commands."

Two cases make this acute:

1. **Sub-agents working in a fresh worktree.** A delegated agent `cd`'s into a worktree and starts running tooling. If the root `.envrc` isn't allowed, every command runs in the wrong env. The agent rarely notices — it just produces work against the wrong nixpkgs / wrong node version / missing secrets — and the human reviewer catches it later. This is the primary motivator.

2. **Nested `.envrc` chains.** `mlsa/src/.envrc` does `source_up; layout node`; the new `mlsa/infra/.envrc` does `use flake ..#infra`. `direnv` does not transitively trust nested envrcs — each must be approved independently. A single `direnv allow` at the root is **not enough**; sub-agents that `cd` into `infra/` or `src/` still get unapproved chains.

Doing this by hand on every `wt add` is friction the human can absorb. Sub-agents can't — they don't know they need to, and they fail silently when they don't.

## Goals

- After `wt add`, **every** `.envrc` in the new worktree is approved by default. Sub-agents (and humans) can `cd` anywhere inside and direnv activates without intervention.
- Discovery is recursive: root + every nested `.envrc`, excluding `.git/`.
- One opt-out flag (`--no-direnv`) for the rare cases where the user wants to inspect before allowing.
- Clear output naming each file that was allowed, so the post-create state is unambiguous.

## Non-goals

- **Copying gitignored files** (`.env`, `node_modules`, etc.) — companion spec.
- **`.wt/config` per-repo configuration** — companion spec.
- **`--json` output for orchestrators** — companion spec.
- **Post-create hooks** — companion spec.
- **Auto-detecting parent-repo envrc** outside the worktree (e.g., a `source_up` reaching above the repo root). Out of scope; rare.

## Design

### 1. Behavior change in `cmd_add`

After the `git worktree add` call (currently around `pkgs/wt/default.nix:109` / `:112`), and before printing the final "Worktree ready" message, run a discovery + approval pass:

```bash
if [ "$skip_direnv" != true ] && command -v direnv >/dev/null 2>&1; then
  local envrc_files=()
  while IFS= read -r f; do envrc_files+=("$f"); done < <(
    find "$wt_path" -name .envrc -not -path '*/.git/*' | sort
  )
  if [ ${#envrc_files[@]} -gt 0 ]; then
    echo ""
    echo "Approving ${#envrc_files[@]} .envrc file(s) with direnv:"
    for f in "${envrc_files[@]}"; do
      direnv allow "$f"
      echo "  allowed: ${f#$wt_path/}"
    done
  fi
fi
```

Key points:

- `find ... -not -path '*/.git/*'` excludes `.git/` (worktrees have a small `.git` file, not a dir, so this is mostly defensive).
- `sort` makes output deterministic across runs.
- `${f#$wt_path/}` strips the worktree prefix so output is relative and short.
- Order doesn't matter to direnv (each `.envrc` is approved independently), but root-first lexical order is the friendliest for humans reading the list.

### 2. New flag: `--no-direnv`

Single opt-out. Last flag wins on conflict (only one flag exists, so this is just future-proofing).

```bash
local skip_direnv=false
# Inline in the existing positional-arg parsing in cmd_add:
while [[ "$1" == --* ]]; do
  case "$1" in
    --no-direnv) skip_direnv=true; shift ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done
```

### 3. Fallback when `direnv` is missing

If `direnv` is not on PATH, the auto-allow loop is skipped silently. We do **not** emit a warn-and-instruct fallback in this MVP — the companion spec adds richer messaging (and JSON output) for orchestrator consumers. For now, missing `direnv` is rare enough that silent skip + the existing "Worktree ready" message is acceptable.

### 4. Trust model

`direnv allow` runs the `.envrc` on first activation. Auto-allowing on `wt add` does not change the trust model:

- The `.envrc` files in question are part of the user's own repo (or a repo they checked out and trust enough to create worktrees of).
- The user already runs `direnv allow` manually after every `wt add` today; we're automating an action they'd take regardless.
- Auto-allow does not extend trust to *new* `.envrc` files appearing after the worktree is created. If someone adds a new `.envrc` mid-branch, direnv's normal "untrusted, run direnv allow" prompt still applies on first cd into that path.

The behavior is symmetric with `git checkout` of `.envrc`-containing branches: the user is already trusting the code they're checking out.

## Trade-offs acknowledged

- **Auto-allow could surprise a user expecting direnv's default friction.** The friction has a purpose: a moment to read a new `.envrc` before it runs. This MVP trades that moment for sub-agent ergonomics. `--no-direnv` exists for users (or sessions) that want the original behavior. We could later add an `WT_NO_DIRENV=1` env var if a session-level toggle becomes useful.

- **`find` walks the whole tree.** Cheap in practice, but unbounded — a worktree containing a vendored monorepo with hundreds of `.envrc`s would approve all of them. Not a problem in current repos; if it becomes one, a depth limit or pattern allowlist belongs in the companion spec's `.wt/config`.

- **No JSON output yet.** Sub-agent orchestrators that want to assert "direnv was activated for X paths" before dispatching work need to scrape stdout. Acceptable for the MVP; companion spec adds `--json`.

## Files touched

- `pkgs/wt/default.nix` — extend `cmd_add` with flag parse + auto-allow loop.
- `pkgs/wt/README.md` — document the new default behavior and `--no-direnv` flag.
- `pkgs/wt/completions/{wt.bash,_wt,wt.fish,wt.nu}` — add `--no-direnv` to `wt add` completions.
- `pkgs/wt/tests/test-add-direnv.sh` — new: covers root-only, nested chain, `--no-direnv`, and missing-direnv scenarios.

## Verification

- `nix build .#wt` succeeds on Linux and Darwin.
- Smoke test in dotfiles: `wt add foo` lists the root `.envrc` as allowed; `cd .worktrees/foo` activates direnv without prompt.
- Smoke test in mlsa: `wt add foo` lists root + `infra/.envrc` + `src/.envrc`; `cd .worktrees/foo/infra` and `cd .worktrees/foo/src` both activate direnv without prompt.
- Sub-agent smoke test: dispatch a subagent into a fresh worktree, ask it to run a tool that only the dev shell provides; the tool resolves correctly without the agent doing any direnv work.
- `wt add foo --no-direnv` skips the loop; original behavior preserved.
- In a shell with `direnv` not on PATH (e.g., `env -i bash` or a minimal container), `wt add foo` still creates the worktree and exits cleanly without errors.

## Open questions

1. **Should `--no-direnv` be available as `WT_NO_DIRENV=1` env var too?** Useful for "this whole agent session, skip direnv" without re-passing the flag. **Recommendation:** defer; add only if we see real demand.

2. **What about `.envrc` files inside symlinked directories within the worktree?** `find` follows symlinks only with `-L`. Without it, a symlinked vendored module with its own `.envrc` is not approved. **Recommendation:** don't follow symlinks (default `find` behavior). Symlinked envrcs are unusual and likely belong to the *target* directory's trust scope, not the worktree's.

3. **Does `direnv allow` need any error handling beyond the `command -v` guard?** It can fail if the `.envrc` has a syntax error. **Recommendation:** let it fail loudly — a broken `.envrc` is a real problem the user should see, and direnv's stderr is informative.
