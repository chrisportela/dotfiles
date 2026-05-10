# `wt add` bootstrap extras (copy, config, hooks, JSON) — design

**Date:** 2026-05-07
**Target package:** `pkgs/wt/`
**Status:** Draft, deferred — depends on MVP shipping first
**Depends on:** [2026-05-07-wt-add-direnv-auto-allow-design.md](./2026-05-07-wt-add-direnv-auto-allow-design.md) — direnv auto-allow is the foundation; this spec layers extras on top.
**Predecessor:** [2026-04-16-wt-completions-squash-merge-design.md](./2026-04-16-wt-completions-squash-merge-design.md) — the rest of the deferred "DF-10" scope.

## Problem

Once direnv auto-allow lands (MVP), `wt add` produces a worktree where tools resolve correctly. Three classes of friction remain:

1. **Gitignored runtime files** (`.env`, `.env.local`, similar) live in the source worktree but not the new one. Today the user `cp`s them by hand, often after a confused stack trace from a tool that expected secrets.

2. **Expensive build artifacts** (`node_modules`, `src/node_modules`, `.next/`, `target/`, etc.) get rebuilt from scratch in every fresh worktree. On CoW filesystems (zfs, btrfs, xfs) `cp --reflink=auto` clones them effectively for free; today wt doesn't do that.

3. **No machine-parseable output.** The "parallel agent fleet across worktrees" pattern (from the recent `/insights` report) needs an orchestrator to assert "this worktree was bootstrapped successfully with X allowed and Y copied" before dispatching work into it. Stdout-scraping is brittle.

These are real but lower-urgency than the MVP's direnv problem — humans can absorb manual copies; sub-agents fail silently without direnv.

## Goals

- Per-repo declarative config at `.wt/config` (TOML) for copy patterns and hook script paths.
- Per-invocation flag overrides: `--copy <pattern>` (repeatable), `--no-copy`, `--json`.
- Optional `.wt/post-create.sh` escape hatch for project-specific bootstrap.
- `--json` output suitable for orchestrator consumption: which `.envrc`s were allowed, which patterns were copied, which were skipped, hook outcome.

## Non-goals

- **Anything direnv-related** — covered by the MVP spec.
- **Replacing existing tools.** No wt-managed package install, no symlink farms, no env layering. wt copies what it's told and runs the hook.
- **Cross-worktree orchestration itself.** wt enables the parallel-agent-fleet pattern via `--json`; the orchestrator runner is its own thing.
- **A `wt rm` symmetric `pre-remove` hook.** Defer to a future spec if a real use case shows up.

## Design

### 1. Per-repo config: `.wt/config` (TOML)

Read by `wt add` from the repo root.

```toml
[copy]
# Paths relative to the source worktree. Globs allowed.
# Each is copied with `cp --reflink=auto -r` to the same relative path
# in the new worktree.
patterns = [
  ".env",
  ".env.local",
  "node_modules",
  "src/node_modules",
]

[hooks]
# Optional. Runs after copy step. Path is relative to the source
# worktree; same script is invoked from inside the new worktree's cwd.
post_create = ".wt/post-create.sh"
```

Notes:

- `.wt/config` itself is **not** auto-copied; copy patterns must be explicit. This is intentional — the config is project-level, not per-worktree.
- The user decides whether `.wt/` is checked in (typical) or `.gitignore`d (per-clone tweaks).
- No `.wt/config` ⇒ no copy step, no hook. The MVP's direnv auto-allow still runs (it doesn't depend on config).

### 2. New flags on `wt add`

| Flag                  | Behavior                                                            |
| --------------------- | ------------------------------------------------------------------- |
| `--copy <pattern>`    | Add `<pattern>` to the copy list. Repeatable. Combines with config. |
| `--no-copy`           | Skip the copy step entirely, even if config has patterns.           |
| `--json`              | Emit a single JSON object summarizing what was done (see §5).       |

`--copy` and `--no-copy` are mutually exclusive; last flag wins on conflict, with a stderr warning.

`--no-direnv` (from MVP) and these flags compose as expected.

### 3. Copy step

`cp --reflink=auto -r <source>/<pattern> <new>/<pattern>` for each pattern that exists in the source worktree. Patterns missing from source are silently skipped (an "expected on some branches, not others" reality, e.g. `node_modules` only exists after a first install).

`--reflink=auto` falls back to a regular copy on filesystems without CoW. The user's primary host (zfs) gets near-instant clones; portability to non-CoW hosts isn't broken.

For directories that don't exist as regular dirs (e.g., a `node_modules` symlinked elsewhere), follow the symlink and copy the target. (See open question §8 — could revisit.)

### 4. Hooks: `.wt/post-create.sh`

Runs after copy. Invoked from the new worktree's cwd. Environment:

| Var             | Value                                                                |
| --------------- | -------------------------------------------------------------------- |
| `WT_BRANCH`     | branch name                                                          |
| `WT_PATH`       | absolute path to the new worktree                                    |
| `WT_SOURCE_DIR` | absolute path of the source worktree (where `wt add` was invoked)    |
| `WT_JSON`       | `1` when `--json` was passed; otherwise unset                        |

Failure mode: non-zero exit prints a warning but does not roll back the worktree. (Rollback would mask real failures and is hard to do correctly — which copies to undo, in what order. Better to leave the artifact and surface the error; user can `wt rm` if they want a clean re-do.)

### 5. JSON output (`--json`)

A single JSON object on stdout. No human-readable text on stdout in `--json` mode (warnings/errors still go to stderr).

```json
{
  "branch": "foo",
  "path": "/abs/path/.worktrees/foo",
  "source_path": "/abs/path",
  "branch_existed": false,
  "envrcs_allowed": [".envrc", "infra/.envrc", "src/.envrc"],
  "envrcs_skipped": false,
  "copied": [".env", "node_modules"],
  "copied_skipped": ["src/node_modules"],
  "hooks_run": [".wt/post-create.sh"],
  "hook_exit": 0,
  "warnings": []
}
```

`copied_skipped` lists patterns from config/flags that didn't exist in source. `envrcs_skipped: true` when `--no-direnv` (MVP flag) was used or direnv isn't installed.

### 6. Implementation sketch in `default.nix`

`cmd_add` gains, layered on top of the MVP's direnv block:

1. Parse new flags from `"$@"`.
2. Read `.wt/config` if present.
3. Run copy step.
4. Run hook if configured.
5. Emit human or JSON summary (replaces the existing "Worktree ready" line in JSON mode).

Helpers (kept in the same file for `writeShellApplication` simplicity):

- `wt_read_config_array <key>` — extract a TOML array of strings.
- `wt_read_config_string <key>` — extract a TOML string.
- `wt_copy_patterns <source> <dest> <pattern>...` — `cp --reflink=auto -r` loop with skip-on-missing.
- `wt_emit_json` — assemble and print the JSON object.

## Trade-offs acknowledged

- **TOML parsing in shell.** A real TOML parser would handle nested tables and string escapes correctly. The keys we need (`copy.patterns`, `hooks.post_create`) are flat enough that a grep+sed reader works for this schema. If `.wt/config` grows, switch to a proper parser. See §8.

- **Copying `node_modules` can be wrong.** Some packages have postinstall scripts that bake absolute paths or platform-specific binaries; reflink-copying them duplicates the bug. Pragmatic answer: opt-in via config — the user knows their stack. pnpm's content-addressed store usually copies cleanly; npm/yarn is more fraught. Documented in `pkgs/wt/README.md`, not policed in code.

- **`.env` files are sensitive.** Copying them spreads secrets across worktrees. Acceptable here (private repos, all worktrees on the same machine), but documented as expected. Users who don't want this set `--no-copy` or omit `.env` from `[copy].patterns`.

- **Hook scripts run untrusted code.** `.wt/post-create.sh` is checked-in (or local) shell, with the same trust model as `direnv` itself or `flake.nix`. Document; don't sandbox.

- **`--json` doesn't capture hook stdout.** Hook output goes to inherited stdout/stderr like any other shell command. Capturing into JSON would surprise hook authors who expect to log progress live. If a fleet orchestrator needs structured hook output, the hook can write to `$WT_PATH/.wt/last-run.json`; not wt's responsibility.

- **No rollback on partial failure.** A failed copy or hook leaves a half-bootstrapped worktree. Rollback would mask real failures; better to leave the artifact and surface the error.

## Files touched

- `pkgs/wt/default.nix` — extend `cmd_add` with flag parse, config reader, copy step, hook runner, JSON emitter.
- `pkgs/wt/README.md` — document new flags, config schema, hook contract, security posture.
- `pkgs/wt/completions/{wt.bash,_wt,wt.fish,wt.nu}` — add `--copy <PATTERN>`, `--no-copy`, `--json` completions.
- `pkgs/wt/tests/` — new tests:
    - `test-add-copy.sh` — config-driven copy + `--copy` flag + `--no-copy`.
    - `test-add-hook.sh` — hook runs, env vars are set, failure surfaces but doesn't roll back.
    - `test-add-json.sh` — `--json` output parses, fields present, composes with `--no-direnv`.

## Verification

- `nix build .#wt` succeeds on Linux and Darwin.
- `nix build .` (full home-manager config) succeeds.
- All `pkgs/wt/tests/*.sh` pass.
- Smoke test in a real project with `.env` and `node_modules`: `wt add foo` copies both; first command in worktree runs without env-loading errors.
- Smoke test of hook: `.wt/post-create.sh` writes a marker file in the new worktree; verify the marker exists and the env vars were correct.
- Backward-compat smoke test: in a repo without `.wt/config` and without flags, `wt add` behaves exactly as MVP (direnv auto-allow only, no copy, no hook).
- `wt add foo --json | jq .` parses; required keys present.

## Open questions

1. **TOML reader: minimal vs. dependency.** Pure-shell grep+sed for the keys we need, or pull `dasel`/`yj`/similar? **Recommendation:** start minimal, document the schema as flat-by-design, switch to a real parser only if the schema grows.

2. **Default copy patterns for unconfigured repos.** Currently "none" — opt-in only. **Recommendation:** keep opt-in. Auto-copying `.env` by default is a security smell; auto-copying `node_modules` is a correctness smell. `.wt/config` is the obvious next step.

3. **`--json` as default in non-TTY contexts.** Detecting `[ -t 1 ]` and switching modes is convenient for orchestrators but adds a hidden mode-switch that surprises in pipes. **Recommendation:** keep `--json` explicit.

4. **Slow-copy warning on non-CoW filesystems.** `--reflink=auto` falls back to deep copy, which can be very slow for large `node_modules`. **Recommendation:** accept; users on non-CoW filesystems can omit those patterns. Optionally warn on first slow copy.

5. **`wt rm` symmetric pre-remove hook.** Out of scope here; revisit if a use case shows up.
