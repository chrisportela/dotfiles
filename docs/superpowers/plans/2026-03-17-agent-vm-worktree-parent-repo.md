# agent-vm: Git Worktree Parent Repo Mounting

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auto-detect git worktrees when creating agent VMs and mount the parent repo into the VM with configurable read/write permissions so Nix flake evaluation and git operations work correctly.

**Architecture:** Three files change: `vm-base.nix` gains two new params and derives virtiofs shares from them; `default.nix` exposes those params as NixOS module options; `agent-vm.nix` adds detection logic in `cmd_create`, a new `--parent-repo-mode` flag, and wires the detected values into the generated flake. Read-only enforcement for `history`/`commit` modes is handled via a `fileSystems` override using `lib.mkForce [ "ro" ]`.

**Tech Stack:** Nix, NixOS module system, bash, microvm.nix virtiofs shares, cloud-hypervisor.

---

## File Map

| File | Change |
|------|--------|
| `modules/nixos/agent-vms/vm-base.nix` | Add `parentRepoPath`/`parentRepoMode` params, `parentRepoShares` let-binding, append to `microvm.shares`, add RO `fileSystems` override |
| `modules/nixos/agent-vms/default.nix` | Add `parentRepoMode` to `templateSubmodule`, add `parentRepoPath`/`parentRepoMode` to `vmSubmodule`, pass both through `mkVm` |
| `modules/nixos/agent-vms/agent-vm.nix` | Add detection block in `cmd_create`, `--parent-repo-mode` flag, validation, `parent_repo_path_nix` expr, extend flake template, extend `cleanTemplate` inherit block, extend `apply_template`, update both completion scripts, update usage |

---

## Task 1: vm-base.nix — parentRepoShares and RO override

**Files:**
- Modify: `modules/nixos/agent-vms/vm-base.nix`

- [ ] **Step 1: Add parameters after `allowSSH` and before `upstreamDNS`**

After `allowSSH ? false, # Allow outbound SSH...` (line 35) and before `upstreamDNS ? [` (line 36), add:

```nix
parentRepoPath ? null,    # Absolute host path to parent repo root (null if not a worktree)
parentRepoMode ? "commit", # "history" | "commit" | "full" | "none"
```

- [ ] **Step 2: Add `parentRepoShares` to the let block**

After the `proxyCAShares` block (after line 104 `];`), add:

```nix
parentRepoShares =
  if parentRepoPath == null || parentRepoMode == "none" then [ ]
  else if parentRepoMode == "history" then [
    { proto = "virtiofs"; tag = "parent-repo"; source = parentRepoPath; mountPoint = parentRepoPath; }
  ]
  else if parentRepoMode == "commit" then [
    { proto = "virtiofs"; tag = "parent-repo";     source = parentRepoPath;           mountPoint = parentRepoPath; }
    { proto = "virtiofs"; tag = "parent-repo-git"; source = "${parentRepoPath}/.git"; mountPoint = "${parentRepoPath}/.git"; }
  ]
  else if parentRepoMode == "full" then [
    { proto = "virtiofs"; tag = "parent-repo"; source = parentRepoPath; mountPoint = parentRepoPath; }
  ]
  else [ ];
```

`history` and `full` produce the same single share — the distinction between them is enforced by the `fileSystems` RO override below, not by the share definition.

- [ ] **Step 3: Append parentRepoShares to microvm.shares**

Change line 158 from:
```nix
    ++ extraShares;
```
to:
```nix
    ++ parentRepoShares
    ++ extraShares;
```

- [ ] **Step 4: Add fileSystems RO override**

In the returned NixOS module config attrset (alongside `microvm`, `networking`, etc.), add:

```nix
# Enforce read-only on parent working tree for history and commit modes.
# microvm.nix generates a virtiofs fileSystems entry from the share; this
# overrides its options to add "ro". lib.mkForce wins over microvm.nix's
# normal-priority definition.
fileSystems = lib.mkIf (
  parentRepoPath != null &&
  (parentRepoMode == "history" || parentRepoMode == "commit")
) {
  "${parentRepoPath}".options = lib.mkForce [ "ro" ];
};
```

Note on mount ordering: NixOS generates systemd `.mount` units from `fileSystems` entries. systemd automatically orders nested mounts by path hierarchy — it adds `After=` for the parent path's mount unit to any mount at a sub-path. The `parent-repo-git` mount unit (`…-parent-.git.mount`) will thus automatically depend on the `parent-repo` mount unit (`…-parent.mount`) with no explicit `depends` needed. This is standard systemd behaviour for nested mount points.

- [ ] **Step 5: Verify the module builds**

```bash
cd /home/cmp/src/dotfiles
nix build .#nixosConfigurations.ada.config.system.build.toplevel --no-link 2>&1 | tail -5
```

Expected: build succeeds (no output or cache hit line). The ada host uses `chrisportela.agent-vms` so this exercises the module.

- [ ] **Step 6: Commit**

```bash
git add modules/nixos/agent-vms/vm-base.nix
git commit -m "feat(agent-vm): add parentRepoPath/parentRepoMode params and virtiofs shares"
```

---

## Task 2: default.nix — NixOS module options and mkVm passthrough

**Files:**
- Modify: `modules/nixos/agent-vms/default.nix`

- [ ] **Step 1: Add `parentRepoMode` to `templateSubmodule`**

In the `templateSubmodule` options block, after the `allowSSH` option, add:

```nix
parentRepoMode = lib.mkOption {
  type = lib.types.nullOr lib.types.str;
  default = null;
  description = "Parent repo access mode when workspace is a worktree: history | commit | full | none";
};
```

- [ ] **Step 2: Add `parentRepoPath` and `parentRepoMode` to `vmSubmodule`**

In the `vmSubmodule` options block, after the `allowSSH` option, add:

```nix
parentRepoPath = lib.mkOption {
  type = lib.types.nullOr lib.types.str;
  default = null;
  description = "Host path to parent repo root. Set automatically for worktree workspaces via agent-vm create.";
};

parentRepoMode = lib.mkOption {
  type = lib.types.str;
  default = "commit";
  description = "Parent repo access mode: history | commit | full | none";
};
```

- [ ] **Step 3: Pass both fields through `mkVm`**

In `mkVm`, add `parentRepoPath` and `parentRepoMode` to the **second** `inherit (vmCfg)` block (the one that includes `copyWorkspace`, `claude`, `allowSSH`, etc. — not the first block that has `ipAddress`, `mac`, `workspace`).

- [ ] **Step 4: Verify build**

```bash
nix build .#nixosConfigurations.ada.config.system.build.toplevel --no-link 2>&1 | tail -5
```

Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add modules/nixos/agent-vms/default.nix
git commit -m "feat(agent-vm): add parentRepoPath/parentRepoMode NixOS module options"
```

---

## Task 3: Write detection test script

**Files:**
- Create: `/tmp/test-detect-worktree.sh` (temporary, not committed)

Write this test before implementing the detection logic in agent-vm.nix. It tests the detection algorithm by sourcing the logic as a standalone function.

- [ ] **Step 1: Write the test script**

Create `/tmp/test-detect-worktree.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

PASS=0; FAIL=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "PASS: $label"
    PASS=$((PASS+1))
  else
    echo "FAIL: $label"
    echo "  expected: '$expected'"
    echo "  actual:   '$actual'"
    FAIL=$((FAIL+1))
  fi
}

# The detection function under test — copy of what will go in agent-vm.nix
# (uses plain coreutils, no Nix path references)
# Caller must set parent_repo_mode before calling.
detect_worktree() {
  local workspace="$1"
  parent_repo_path=""

  # Skip detection entirely when mode is "none"
  if [ "${parent_repo_mode:-commit}" = "none" ]; then return; fi

  if [ ! -f "$workspace/.git" ]; then return; fi

  local gitdir_raw
  gitdir_raw="$(grep '^gitdir:' "$workspace/.git" | head -1 | sed 's/^gitdir: *//')"
  [ -n "$gitdir_raw" ] || return

  local gitdir_abs
  if [[ "$gitdir_raw" = /* ]]; then
    gitdir_abs="$gitdir_raw"
  else
    gitdir_abs="$(realpath -m "$workspace/$gitdir_raw")"
  fi

  if ! echo "$gitdir_abs" | grep -qE '/\.git/worktrees/[^/]+$'; then
    echo "Warning: workspace .git points to unexpected path '$gitdir_raw'; skipping" >&2
    return
  fi

  local parent_git="${gitdir_abs%/worktrees/*}"
  local detected_parent="${parent_git%/.git}"

  if [[ "$workspace" == "$detected_parent"/* ]]; then
    echo "Warning: workspace is nested inside parent repo — not supported in this layout" >&2
    return
  fi

  parent_repo_path="$detected_parent"
}

# --- Setup ---
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# Create parent repo
PARENT="$TMPDIR/myrepo"
git init -q "$PARENT"
git -C "$PARENT" commit -q --allow-empty -m "init"
git -C "$PARENT" config user.email "test@test.com"
git -C "$PARENT" config user.name "Test"

# Create worktree at sibling path
WT="$TMPDIR/myrepo-wt"
git -C "$PARENT" worktree add -q "$WT" HEAD

# Create plain (non-worktree) dir
PLAIN="$TMPDIR/plain"
mkdir "$PLAIN"

# Create nested worktree (inside parent)
NESTED="$PARENT/nested-wt"
git -C "$PARENT" worktree add -q "$NESTED" HEAD

# --- Tests ---

# 1. Plain directory: no detection
parent_repo_path=""; parent_repo_mode="commit"
detect_worktree "$PLAIN"
assert_eq "plain dir: no parent_repo_path" "" "$parent_repo_path"

# 2. Sibling worktree: detects correct parent
parent_repo_path=""; parent_repo_mode="commit"
detect_worktree "$WT"
assert_eq "sibling worktree: parent_repo_path" "$PARENT" "$parent_repo_path"

# 3. Nested worktree: skipped with warning
parent_repo_path=""; parent_repo_mode="commit"
detect_worktree "$NESTED" 2>/dev/null
assert_eq "nested worktree: parent_repo_path empty" "" "$parent_repo_path"

# 4. Parent dir itself (has .git dir, not file): no detection
parent_repo_path=""
parent_repo_mode="commit"
detect_worktree "$PARENT"
assert_eq "parent repo itself: no detection (.git is a dir)" "" "$parent_repo_path"

# 5. mode=none: detection suppressed even for valid worktree
parent_repo_path=""
parent_repo_mode="none"
detect_worktree "$WT" 2>/dev/null
assert_eq "mode=none: detection suppressed" "" "$parent_repo_path"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Run it — confirm all tests pass**

```bash
bash /tmp/test-detect-worktree.sh
```

Expected: all 5 tests PASS, 0 FAIL. The test script contains its own inline copy of the detection function, so it passes immediately. This validates the algorithm is correct *before* wiring it into the Nix build.

---

## Task 4: agent-vm.nix — detection, flag, flake template

**Files:**
- Modify: `modules/nixos/agent-vms/agent-vm.nix`

- [ ] **Step 1: Add local variables to `cmd_create`**

After `local allow_ssh="false"` (line 218), add:

```bash
local parent_repo_path=""
local parent_repo_mode="commit"
```

- [ ] **Step 2: Add `--parent-repo-mode` to the flag-parsing loop**

In the `while [ $# -gt 0 ]` case statement (after `--allow-ssh`), add before the `*) echo "Unknown flag"` catch-all:

```bash
--parent-repo-mode) parent_repo_mode="$2"; shift 2 ;;
```

- [ ] **Step 3: Add validation after the `--network-mode` validation block**

After lines 246–249 (the network_mode validation), add:

```bash
if [ "$parent_repo_mode" != "history" ] && \
   [ "$parent_repo_mode" != "commit" ] && \
   [ "$parent_repo_mode" != "full" ] && \
   [ "$parent_repo_mode" != "none" ]; then
  echo "Error: --parent-repo-mode must be 'history', 'commit', 'full', or 'none'" >&2
  exit 1
fi
```

- [ ] **Step 4: Add the worktree detection block**

After the `parent_repo_mode` validation (Step 3) and before `local vm_dir=`, add:

```bash
# Detect git worktree and auto-mount parent repo.
# Skip detection entirely if mode is "none" — user explicitly opted out.
if [ "$parent_repo_mode" != "none" ] && [ -n "$workspace" ] && [ -f "$workspace/.git" ]; then
  local gitdir_raw
  gitdir_raw="$(${pkgs.gnugrep}/bin/grep '^gitdir:' "$workspace/.git" | head -1 | ${pkgs.gnused}/bin/sed 's/^gitdir: *//')"
  if [ -n "$gitdir_raw" ]; then
    local gitdir_abs
    if [[ "$gitdir_raw" = /* ]]; then
      gitdir_abs="$gitdir_raw"
    else
      gitdir_abs="$(${pkgs.coreutils}/bin/realpath -m "$workspace/$gitdir_raw")"
    fi
    if echo "$gitdir_abs" | ${pkgs.gnugrep}/bin/grep -qE '/\.git/worktrees/[^/]+$'; then
      local parent_git="${gitdir_abs%/worktrees/*}"
      local detected_parent="${parent_git%/.git}"
      if [[ "$workspace" == "$detected_parent"/* ]]; then
        echo "Warning: workspace is nested inside parent repo — parent repo mount not supported in this layout" >&2
      else
        parent_repo_path="$detected_parent"
        echo "Warning: workspace is a git worktree of $detected_parent (parent-repo-mode: $parent_repo_mode)" >&2
      fi
    else
      echo "Warning: workspace .git points to an unexpected path '$gitdir_raw'; skipping parent repo mount" >&2
    fi
  fi
fi
```

- [ ] **Step 5: Add `parent_repo_path_nix` expression builder**

After the `dotfiles_dir_nix` block (around lines 401–403), add:

```bash
# Build parent repo path Nix expression
local parent_repo_path_nix="null"
if [ -n "$parent_repo_path" ]; then
  parent_repo_path_nix="\"$parent_repo_path\""
fi
```

- [ ] **Step 6: Add the two new params to the generated flake.nix**

In the `sudo tee "$vm_dir/flake.nix"` heredoc, inside the `vm-base.nix` call (after `allowSSH = $allow_ssh;`), add:

```nix
              parentRepoPath = $parent_repo_path_nix;
              parentRepoMode = "$parent_repo_mode";
```

- [ ] **Step 7: Add `parentRepoMode` to `cleanTemplate`**

In the `cleanTemplate` let-binding, add `parentRepoMode` to the `inherit (t)` block alongside `allowSSH`.

- [ ] **Step 8: Add `parentRepoMode` to `apply_template`**

In `apply_template`, after the `allow_ssh` line (line 195), add:

```bash
val="$(echo "$tpl" | ${pkgs.jq}/bin/jq -r '.parentRepoMode // empty')" && [ -n "$val" ] && parent_repo_mode="$val"
```

- [ ] **Step 9: Verify build**

```bash
nix build .#nixosConfigurations.ada.config.system.build.toplevel --no-link 2>&1 | tail -5
```

Expected: build succeeds.

- [ ] **Step 10: Commit**

```bash
git add modules/nixos/agent-vms/agent-vm.nix
git commit -m "feat(agent-vm): detect git worktrees and mount parent repo with --parent-repo-mode"
```

---

## Task 5: agent-vm.nix — completions and usage

**Files:**
- Modify: `modules/nixos/agent-vms/agent-vm.nix`

- [ ] **Step 1: Update usage text**

In the `usage()` heredoc, add `--parent-repo-mode` to the Create flags section:

```
  --parent-repo-mode <mode>       Parent repo access: history|commit|full|none (default: commit)
```

- [ ] **Step 2: Update bash completion — create_flags**

On line 749, add `--parent-repo-mode` to the `create_flags` string.

- [ ] **Step 3: Update bash completion — value completion for `--parent-repo-mode`**

In the `case "$prev"` block inside `create)`, add a new case after `--network-mode`:

```bash
--parent-repo-mode)
  COMPREPLY=( $(compgen -W "history commit full none" -- "$cur") )
  return
  ;;
```

- [ ] **Step 4: Update zsh completion**

In the `create)` case `_arguments` call, add after the `--network-mode` line:

```
'--parent-repo-mode[Parent repo access mode]:mode:(history commit full none)' \
```

- [ ] **Step 5: Verify full build**

```bash
nix build .#nixosConfigurations.ada.config.system.build.toplevel --no-link 2>&1 | tail -5
```

Expected: build succeeds.

- [ ] **Step 6: Commit**

```bash
git add modules/nixos/agent-vms/agent-vm.nix
git commit -m "feat(agent-vm): add --parent-repo-mode completions and usage text"
```

---

## Task 6: Integration smoke test

This task verifies end-to-end behaviour without starting a VM (which requires the full host setup). It checks the generated flake.nix contains correct values.

- [ ] **Step 1: Create a test repo and worktree**

```bash
TESTDIR=$(mktemp -d)
git init -q "$TESTDIR/myrepo"
git -C "$TESTDIR/myrepo" commit -q --allow-empty -m "init"
git -C "$TESTDIR/myrepo" config user.email "test@test.com"
git -C "$TESTDIR/myrepo" config user.name "Test"
git -C "$TESTDIR/myrepo" worktree add -q "$TESTDIR/myrepo-wt" HEAD
echo "Worktree: $TESTDIR/myrepo-wt"
echo "Parent:   $TESTDIR/myrepo"
```

- [ ] **Step 2: Run agent-vm create in dry-run mode (inspect output)**

```bash
# This creates the VM dir but doesn't start it — safe to inspect then destroy
sudo agent-vm create smoke-test-wt --workspace "$TESTDIR/myrepo-wt" 2>&1
```

Expected output includes:
```
Warning: workspace is a git worktree of <TESTDIR>/myrepo (parent-repo-mode: commit)
Creating VM 'smoke-test-wt' with IP ...
```

- [ ] **Step 3: Verify generated flake.nix**

```bash
sudo grep -A2 "parentRepo" /var/lib/microvms/smoke-test-wt/flake.nix
```

Expected:
```nix
              parentRepoPath = "<TESTDIR>/myrepo";
              parentRepoMode = "commit";
```

- [ ] **Step 4: Test `--parent-repo-mode history` override**

```bash
sudo agent-vm create smoke-test-ro --workspace "$TESTDIR/myrepo-wt" --parent-repo-mode history 2>&1
sudo grep -A2 "parentRepo" /var/lib/microvms/smoke-test-ro/flake.nix
```

Expected: `parentRepoMode = "history";`

- [ ] **Step 5: Test `--parent-repo-mode none` suppresses detection**

```bash
sudo agent-vm create smoke-test-none --workspace "$TESTDIR/myrepo-wt" --parent-repo-mode none 2>&1
```

Expected: **no** `Warning: workspace is a git worktree` line in output (detection is skipped entirely when mode is `none`).

```bash
sudo grep "parentRepoPath" /var/lib/microvms/smoke-test-none/flake.nix
```

Expected: `parentRepoPath = null;`

- [ ] **Step 6: Cleanup**

```bash
sudo agent-vm destroy smoke-test-wt
sudo agent-vm destroy smoke-test-ro
sudo agent-vm destroy smoke-test-none
rm -rf "$TESTDIR"
rm -f /tmp/test-detect-worktree.sh
```

- [ ] **Step 7: Final nix flake check**

```bash
nix flake check --all-systems 2>&1 | tail -10
```

Expected: all checks pass.
