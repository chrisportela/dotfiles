# `wt add` worktree bootstrap (env, direnv, copy) — design

**Date:** 2026-05-07
**Target package:** `pkgs/wt/`
**Status:** Draft, pending review
**Predecessor:** [2026-04-16-wt-completions-squash-merge-design.md](./2026-04-16-wt-completions-squash-merge-design.md) — explicitly deferred this work as "DF-10".

## Problem

After `wt add <branch>`, the new worktree is **not ready to work in**. Several manual steps stand between "tree exists" and "tools that the project expects are actually on PATH and configured":

1. **`direnv allow` on the root `.envrc`** — without this, the worktree's `.envrc` is inert; tools provided by the dev shell (or `dotenv_if_exists`-loaded secrets) silently fail to load. Commands then run with whatever's on the global PATH, which is sometimes wrong, sometimes missing.

2. **`direnv allow` on every nested `.envrc`** — projects with sub-shells per area (e.g., `mlsa/infra/.envrc` does `use flake ..#infra`, `mlsa/src/.envrc` does `source_up; layout node`) need each one approved separately. `direnv` does **not** transitively trust nested envrcs; the user has to `cd` into each subdir or pass each path. This is the silent failure mode that prompted this spec — `mlsa/src/.envrc` already existed when `wt add` was created and never auto-activates; `mlsa/infra/.envrc` is new and will hit the same wall.

3. **Copying gitignored runtime files** — `.env`, `.env.local`, and similar are intentionally not in git but are needed at runtime. They live in the source worktree but not the new one. Today the user `cp`'s them by hand, often after a confused stack trace.

4. **Reusing expensive build artifacts** — `node_modules`, `src/node_modules`, `.next/`, `target/`, etc. would otherwise be rebuilt from scratch in every new worktree. With CoW filesystems (zfs, btrfs, xfs) `cp --reflink=auto` clones them effectively for free; without that, the new worktree pays a full reinstall on first run.

The pain compounds in proportion to how often new worktrees are created — which, per the user's recent insights report, is rising fast (148 commits across 47 sessions, with a "parallel agent fleet across worktrees" pattern emerging as a near-term workflow goal). Bootstrap friction that's tolerable for one worktree per day becomes a blocker at four worktrees per ticket.

## Goals

- After `wt add <branch>`, the new worktree is **ready to start work in** by default: `.envrc`s are allowed, configured runtime files are copied, the user can `cd` and run project commands.
- Behavior is **configurable per-repo** via `.wt/config` and **overridable per-invocation** via flags.
- Sensible **fallback for unconfigured repos**: don't copy anything, but emit a precise warn-and-instruct checklist of `.envrc` files the user still needs to allow.
- Output remains human-readable. Add **machine-parseable `--json` mode** for orchestrators (the parallel-agent-fleet pattern from the insights report — orchestrator agents need to know which envrcs were allowed and which files were copied to decide if the worktree is healthy).
- Treat each bootstrap step as **explicit and named** in the output (per insights "Worktree & path discipline" / "Verify live state" themes — the post-create state should be unambiguous, not implicit).

## Non-goals

- **Running tests, builds, or `nix flake check`** in the new worktree. wt creates worktrees; it doesn't validate them. A separate verification skill or CI hook owns that.
- **Replacing `direnv`** with a wt-internal env mechanism. direnv stays the source of truth; wt only handles approval.
- **Shell-side auto-`cd`** into the new worktree. That's a per-shell concern (alias / function in `shell_functions.sh`); out of scope for the package.
- **Cross-worktree orchestration** (the parallel-agent-fleet runner itself). wt enables it via `--json`; the orchestrator is its own thing.
- **A `wt rm` symmetric `pre-remove` hook.** Deferred; not required for this milestone.

## Design

### 1. Per-repo config: `.wt/config`

A small TOML file at the repo root. Read by `wt add`. Schema:

```toml
[copy]
# Patterns are paths relative to the source worktree. Globs allowed.
# Each is copied with `cp --reflink=auto -r` to the same relative path
# in the new worktree.
patterns = [
  ".env",
  ".env.local",
  "node_modules",
  "src/node_modules",
]

[direnv]
allow_root   = true   # run `direnv allow` on the worktree root
allow_nested = true   # walk the tree and allow every .envrc

[hooks]
# Optional escape hatch. Runs after copy and direnv steps complete.
# Path is relative to the source worktree; same script is invoked from
# inside the new worktree's cwd.
post_create = ".wt/post-create.sh"
```

`.wt/config` itself **is not auto-copied** — copying patterns belong in `[copy]` to keep the config explicit. The user decides whether `.wt/` is checked in (typical) or `.gitignore`d (per-clone tweaks).

If no `.wt/config` exists, defaults are: copy nothing; allow root `.envrc` only; emit warn-and-instruct for nested ones.

### 2. New flags on `wt add`

| Flag                    | Behavior                                                          |
| ----------------------- | ----------------------------------------------------------------- |
| `--copy <pattern>`      | Add `<pattern>` to the copy list. Repeatable. Combines with config. |
| `--no-copy`             | Skip the copy step entirely, even if config has patterns.         |
| `--direnv`              | Force direnv allow (root + nested), regardless of config.         |
| `--no-direnv`           | Skip direnv approval; emit the warn-and-instruct checklist.       |
| `--json`                | Emit a single JSON object summarizing what was done (see §6).     |

`--copy` and `--no-copy` are mutually exclusive; same for `--direnv` / `--no-direnv`. Last flag wins on conflict, with a stderr warning.

### 3. Copy step

`cp --reflink=auto -r <source>/<pattern> <new>/<pattern>` for each pattern that exists in the source worktree. Patterns missing from source are silently skipped (an "expected on some branches, not others" reality, e.g. `node_modules` only exists after a first install).

`--reflink=auto` falls back to a regular copy on filesystems without CoW; the user's primary host (zfs) gets near-instant clones; portability to non-CoW hosts isn't broken.

For directories that don't exist as regular dirs (e.g., a `node_modules` symlinked elsewhere), follow the symlink and copy the target. (Open question — see §10.)

### 4. direnv allow step

Locate every `.envrc` under the new worktree, excluding `.git/`:

```bash
find "$wt_path" -name .envrc -not -path '*/.git/*'
```

Order: root first, then sub-dirs in lexical order (deterministic, but order doesn't actually matter to direnv — each `.envrc` is approved independently).

For each, run `direnv allow "<path>"`. If `direnv` isn't on PATH, skip the whole step and emit warn-and-instruct (§5) regardless of `--direnv`.

`source_up` chains are handled implicitly: each `.envrc` along the chain is approved independently. The mlsa case (`src/.envrc` does `source_up`; root `.envrc` is the parent) works because both files end up approved.

### 5. Warn-and-instruct fallback

When `--no-direnv` is in effect (or direnv isn't installed), print exactly:

```
Worktree ready at .worktrees/<branch>
.envrc files awaiting approval:
  - .envrc
  - infra/.envrc
  - src/.envrc
To activate, run:
  ( cd .worktrees/<branch> && \
      while IFS= read -r f; do direnv allow "$f"; done \
        < <(find . -name .envrc -not -path './.git/*') )
```

Names every file. Gives a copy-pasteable one-liner. The same listing is included in `--json` output's `envrcs_pending` field.

### 6. JSON output (`--json`)

A single JSON object on stdout. No human-readable text on stdout in `--json` mode (warnings/errors still go to stderr).

```json
{
  "branch": "foo",
  "path": "/abs/path/.worktrees/foo",
  "source_path": "/abs/path",
  "branch_existed": false,
  "copied": [".env", "node_modules"],
  "copied_skipped": ["src/node_modules"],
  "envrcs_allowed": [".envrc", "infra/.envrc", "src/.envrc"],
  "envrcs_pending": [],
  "hooks_run": [".wt/post-create.sh"],
  "warnings": []
}
```

`copied_skipped` lists patterns from config/flags that didn't exist in source. `envrcs_pending` is non-empty when `--no-direnv` was used or direnv isn't installed.

### 7. Hooks: `.wt/post-create.sh`

Runs after copy + direnv. Invoked from the new worktree's cwd. Environment:

| Var             | Value                                            |
| --------------- | ------------------------------------------------ |
| `WT_BRANCH`     | branch name                                      |
| `WT_PATH`       | absolute path to the new worktree                |
| `WT_SOURCE_DIR` | absolute path of the source worktree (where `wt add` was invoked) |
| `WT_JSON`       | `1` when `--json` was passed; otherwise unset    |

Failure mode: non-zero exit prints a warning but does not roll back the worktree. (Rollback would be misleading — the worktree is created, just not fully bootstrapped.)

### 8. Implementation sketch in `default.nix`

`cmd_add` gains, after the `git worktree add` line and before the final "Worktree ready" message:

1. Parse new flags from `"$@"`.
2. Read `.wt/config` if present (TOML parsing in pure shell is unpleasant; pull a small helper — `dasel` or `taplo` would be heavy. **Open question, §10**: implement a minimal grep-based reader for the four keys we need, or accept a dep).
3. Run copy step.
4. Run direnv step (or emit warn-and-instruct).
5. Run hook if configured.
6. Emit human or JSON summary.

Helpers (kept in the same file for `writeShellApplication` simplicity):

- `wt_read_config_array <key>` — extract a TOML array of strings.
- `wt_read_config_bool <key>` — extract a TOML boolean.
- `wt_copy_patterns <source> <dest> <pattern>...` — `cp --reflink=auto -r` loop with skip-on-missing.
- `wt_allow_envrcs <path>` — find + direnv allow loop.
- `wt_emit_json` — assemble and print the JSON object.

### 9. Connection to the insights report

This work directly addresses three patterns surfaced by `/insights`:

- **"Worktree & path discipline" (Quick wins).** New worktrees being silently under-bootstrapped is exactly the failure mode that produces wrong-target edits and confused environments. Naming every step in the output (envrc list, copied files, JSON keys) makes the post-create state unambiguous.
- **"Parallel Agent Fleet Across Worktrees" (On the horizon).** A four-agent overnight fleet can't tolerate manual `direnv allow` between dispatches. `--json` output and config-driven defaults are prerequisites for that workflow.
- **"Verify live state before editing" theme.** Whether the operator is the human or an agent, the surface area of "what's been done" needs to be small and explicit. The warn-and-instruct fallback exists specifically so the absence of allowed envrcs is loud, not silent.

## Trade-offs acknowledged

- **TOML parsing in shell.** A real TOML parser would handle nested tables and string escapes correctly. The four keys we need (`copy.patterns`, `direnv.allow_root`, `direnv.allow_nested`, `hooks.post_create`) are flat enough that a grep+sed reader works for our actual schema. If `.wt/config` grows beyond this, switch to a proper parser. See §10.

- **Copying `node_modules` can be wrong.** Some packages have postinstall scripts that bake absolute paths or platform-specific binaries; reflink-copying them duplicates the bug. The pragmatic answer: this is opt-in via config — the user knows their stack. Where pnpm's content-addressed store is in use, copying `node_modules` is mostly symlink-rewriting and works fine; with npm/yarn it's more fraught. Documented in `pkgs/wt/README.md`, not policed in code.

- **`.env` files are sensitive.** Copying them spreads secrets across worktrees. Acceptable here (private repos, all worktrees on the same machine), but documented as expected behavior. Users who don't want this set `--no-copy` or omit `.env` from `[copy].patterns`.

- **Nested direnv allow can balloon.** A monorepo with N `.envrc`s costs N approvals per `wt add`. Acceptable; if it bites later, add `direnv.nested_max_depth` or `direnv.nested_skip` config keys.

- **Hook scripts run untrusted code.** `.wt/post-create.sh` is checked-in (or local) shell, with the same trust model as `direnv` itself or `flake.nix`. Document; don't sandbox.

- **`--json` doesn't include hook stdout.** Hook output goes to inherited stdout/stderr like any other shell command. Capturing into JSON would surprise hook authors who expect to log progress live. If a fleet orchestrator needs structured hook output, it can write to a file at `$WT_PATH/.wt/last-run.json`; not wt's responsibility.

- **No rollback on partial failure.** A failed copy or hook leaves a half-bootstrapped worktree. Rollback would mask real failures and is hard to do correctly (which copies to undo, in what order). Better to leave the artifact and surface the error; user can `wt rm` if they want a clean re-do.

## Files touched

- `pkgs/wt/default.nix` — extend `cmd_add` with flag parsing, config reader, copy step, direnv step, hook runner, JSON emitter; add helper functions.
- `pkgs/wt/README.md` — document new flags, config schema, hook contract, security posture.
- `pkgs/wt/completions/{wt.bash,_wt,wt.fish,wt.nu}` — add `--copy <PATTERN>`, `--no-copy`, `--direnv`, `--no-direnv`, `--json` completions.
- `pkgs/wt/tests/` — new tests:
    - `test-add-copy.sh` — config-driven copy + `--copy` flag + `--no-copy`.
    - `test-add-direnv.sh` — root-only and nested allow; `--no-direnv` fallback.
    - `test-add-hook.sh` — hook runs, env vars are set, failure surfaces but doesn't roll back.
    - `test-add-json.sh` — `--json` output parses, fields present.

## Verification

- `nix build .#wt` succeeds on Linux and Darwin.
- `nix build .` (full home-manager config) succeeds.
- All `pkgs/wt/tests/*.sh` pass.
- Smoke test in dotfiles itself: `wt add foo` emits the same output as today plus an "envrc allowed" line for the root `.envrc` (once `.wt/config` is added with sensible defaults).
- Smoke test in mlsa: `wt add foo` activates root + `infra/.envrc` + `src/.envrc`; running `which <tool-from-flake>` in `infra/` and `src/` resolves to the dev-shell-provided binary.
- Backward-compat smoke test: in a repo without `.wt/config` and without flags, `wt add` continues to work; nothing is copied; warn-and-instruct lists the discovered envrcs.
- `wt add foo --json | jq .` parses; required keys present.

## Open questions / explicit deferrals

1. **TOML reader: minimal vs. dependency.** Pure-shell grep+sed for the four keys, or pull `dasel`/`yj`/similar? **Recommendation:** start minimal, document the schema as flat-by-design, switch to a real parser only if the schema grows.

2. **Default copy patterns for unconfigured repos.** Currently "none" — opt-in only. **Recommendation:** keep opt-in. Auto-copying `.env` by default is a security smell; auto-copying `node_modules` is a correctness smell. Better to make `.wt/config` the obvious next step.

3. **Auto-cd into the new worktree.** Tempting but shell-specific. **Recommendation:** out of scope; add a shell function in `shell_functions.sh` later if needed (e.g., `wta` = `wt add && cd "$(...)"`).

4. **`--json` as default in non-TTY contexts.** Detecting `[ -t 1 ]` and switching modes is convenient for orchestrators but adds a hidden mode-switch that surprises in pipes. **Recommendation:** keep `--json` explicit; orchestrators can pass it.

5. **Copying expensive build artifacts on non-CoW filesystems.** `--reflink=auto` falls back to deep copy, which can be very slow for large `node_modules`. **Recommendation:** accept; users on non-CoW filesystems can omit those patterns from `[copy]`. Optionally warn on first slow copy.

6. **`wt rm` symmetric pre-remove hook.** Out of scope here; revisit in a future spec if a real use case shows up.
