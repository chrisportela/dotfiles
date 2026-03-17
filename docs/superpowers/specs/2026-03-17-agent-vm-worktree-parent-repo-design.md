# agent-vm: Git Worktree Parent Repo Mounting

**Date:** 2026-03-17
**Status:** Approved

## Problem

When a workspace passed to `agent-vm create` is a git worktree, its `.git` entry is a file (not a directory) that points to the parent repo's `.git` directory via an absolute path (e.g. `gitdir: /home/cmp/src/myrepo/.git/worktrees/my-feature`). Because only the worktree directory is mounted into the VM, the parent `.git` is unreachable. This causes two concrete failures:

1. **Nix flake evaluation fails** — Nix reads the git index to determine which files are tracked; without the parent `.git` objects database it cannot evaluate the flake at all.
2. **Git history and commits are unavailable** — all git operations that traverse the object store fail.

## Solution Overview

Auto-detect worktrees at `agent-vm create` time, print a notice, and mount the parent repo's directory into the VM according to a configurable permission mode. The default mode allows committing while keeping the parent working tree read-only.

## Modes

| Mode | Parent working tree | Parent `.git` | Use case |
|------|-------------------|---------------|----------|
| `history` | RO | RO | Read log/blame, Nix flake eval; no commits |
| `commit` *(default)* | RO | RW | Commit from worktree; see parent code; cannot modify parent branch files |
| `full` | RW | RW | Full access to parent repo |
| `none` | — | — | Explicitly disable; accepts broken flake eval |

## Detection

In `cmd_create`, after `workspace` is resolved:

1. Check if `$workspace/.git` is a regular file.
2. If yes: read the `gitdir:` line and strip the `gitdir: ` prefix.
3. Canonicalise to an absolute path using `realpath -m` relative to `$workspace` (the gitdir value may be relative, e.g. `../.git/worktrees/my-feature`).
4. Verify the resolved path contains the `worktrees/` component. If it does not match the expected `<dotgit>/worktrees/<name>` pattern, print a warning and skip parent repo mounting: `Warning: workspace .git points to an unexpected path '<value>'; skipping parent repo mount`.
5. Strip the `worktrees/<name>` suffix → parent `.git` path.
6. Strip `/.git` suffix → parent repo root.
7. Check whether `parent_repo_path` is a path prefix of `workspace` (worktree nested inside parent). If yes, print a warning and skip: `Warning: workspace is nested inside parent repo — parent repo mount not supported in this layout`.
8. Print: `Warning: workspace is a git worktree of /home/cmp/src/myrepo (parent-repo-mode: commit)` (uses `Warning:` for consistency with existing output conventions).
9. Set `parent_repo_path` and `parent_repo_mode="commit"`.

If `--parent-repo-mode none` is passed, the parent is not mounted even if a worktree was detected. If the workspace is not a worktree, `parentRepoPath` is null and no parent shares are added regardless of mode. If `--parent-repo-mode` is given an invalid value, fail with an error matching the existing `--network-mode` validation pattern.

## CLI

New flag added to `agent-vm create`:

```
--parent-repo-mode <mode>   history | commit | full | none
                            Override the default (commit) when a worktree is detected.
```

Completions added for both bash and zsh.

## vm-base.nix

Two new parameters:

```nix
parentRepoPath ? null,    # Absolute path to parent repo root (null if not a worktree)
parentRepoMode ? "commit", # "history" | "commit" | "full" | "none"
```

Shares generated:

```nix
parentRepoShares =
  if parentRepoPath == null || parentRepoMode == "none" then []
  else if parentRepoMode == "history" then [
    { proto = "virtiofs"; tag = "parent-repo";     source = parentRepoPath;           mountPoint = parentRepoPath; }
  ]
  else if parentRepoMode == "commit" then [
    { proto = "virtiofs"; tag = "parent-repo";     source = parentRepoPath;           mountPoint = parentRepoPath; }
    { proto = "virtiofs"; tag = "parent-repo-git"; source = "${parentRepoPath}/.git"; mountPoint = "${parentRepoPath}/.git"; }
  ]
  else if parentRepoMode == "full" then [
    { proto = "virtiofs"; tag = "parent-repo";     source = parentRepoPath;           mountPoint = parentRepoPath; }
  ]
  else [];
```

Appended to `microvm.shares` alongside the existing share lists.

**Read-only enforcement** for `history` and `commit` modes: microvm.nix does not expose a `readOnly` field on shares, so RO is enforced via a `fileSystems` override in vm-base.nix adding `options = [ "ro" ]` to the parent working tree mount. The virtiofsd daemon exports RW; the kernel enforces RO at mount time. The `history` and `full` share expressions are identical — the distinction between them is expressed entirely through this `fileSystems` override (RO for `history`, no override for `full`).

**Mount layering** for `commit` mode: the `.git` share mounts at `<parent>/.git` on top of the parent working tree share at `<parent>/`. Standard Linux mount layering — the inner mount takes precedence for that path. No overlayfs or in-VM scripting required. Mount ordering must be enforced: the `parent-repo-git` fileSystems entry must declare `depends = [ "<parent>" ]` so systemd activates the parent working tree mount first.

**Two virtiofsd processes in `commit` mode**: the `parent-repo` and `parent-repo-git` shares each spawn a virtiofsd process, and their host source directories overlap (`<parent>/` and `<parent>/.git/`). This is safe: virtiofsd is a passthrough FUSE daemon — it does not buffer or cache writes independently. Concurrent access to the same host filesystem paths from two virtiofsd instances is handled by the host kernel's VFS layer exactly as two concurrent processes accessing the same files would be. No additional locking is required.

## agent-vm.nix (shell script)

- `cmd_create` gains `parent_repo_path=""` and `parent_repo_mode="commit"` local variables.
- Worktree detection block runs after workspace resolution (see Detection section).
- `--parent-repo-mode` parsed in the flag loop; invalid values fail with an error (same pattern as `--network-mode` validation at lines 246–249).
- Flake template passes `parentRepoPath` and `parentRepoMode` to vm-base.nix.
- `cleanTemplate` gains `parentRepoMode` in the `inherit` block. The outer `lib.filterAttrs (_: v: v != null)` drops it when null, so no per-field null expression is needed.
- `apply_template` reads `.parentRepoMode // empty` from the template JSON (same jq pattern as other fields) and sets `parent_repo_mode`. When the field is absent or null in the JSON, the shell variable retains its default value of `"commit"`.
- `agent-vm update` does **not** re-run worktree detection. `parentRepoPath` and `parentRepoMode` are baked into `flake.nix` at create time and `update` only overwrites `vm-base.nix` and `vm-network.nix` from the baked-in versions.
- Bash and zsh completions updated with `--parent-repo-mode` and its values `history commit full none`.
- Usage text updated.

## default.nix (NixOS module)

- `templateSubmodule`: add `parentRepoMode` (nullable string, default null).
- `vmSubmodule`: add `parentRepoPath` (nullable string, default null) and `parentRepoMode` (string, default `"commit"`).
- `mkVm`: pass both fields through to vm-base.nix.

## Files Changed

| File | Change |
|------|--------|
| `modules/nixos/agent-vms/agent-vm.nix` | Detection, flag, flake template, completions |
| `modules/nixos/agent-vms/vm-base.nix` | New params, `parentRepoShares`, RO fileSystems |
| `modules/nixos/agent-vms/default.nix` | New options in templateSubmodule/vmSubmodule, mkVm passthrough |
