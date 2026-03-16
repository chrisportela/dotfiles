# Agent VMs Tool Defaults & Home Manager Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-tool flags (`--claude`, `--direnv`) and home-manager integration to agent VMs so tools like Claude Code work out of the box.

**Architecture:** Extend the three existing files (`default.nix`, `agent-vm.nix`, `vm-base.nix`) with new options, CLI flags, and home-manager user configuration. The `homeManagerModule` is passed as a parameter to `vm-base.nix` since it has no access to flake inputs directly.

**Tech Stack:** NixOS module system, home-manager, microvm.nix, bash (writeShellScriptBin)

**Prerequisites:** The host flake must have `home-manager` as an input and pass it via `specialArgs` to NixOS modules. The dotfiles flake already does this (see `flake.nix` lines 20-21 and 236).

**Note on `claude-code` package:** `claude-code` is not in nixpkgs. The `--claude` flag handles credential sharing and config seeding only. Users install the `claude` binary separately via `--packages`, `--hm-module`, or an overlay. If/when `claude-code` is available in the host's nixpkgs/overlays, the flag can be extended to include it automatically.

**Spec:** `docs/superpowers/specs/2026-03-14-agent-vms-tool-defaults-design.md`

---

## Chunk 1: Home Manager Integration in vm-base.nix

### Task 1: Add home-manager parameters and imports to vm-base.nix

**Files:**
- Modify: `modules/nixos/agent-vms/vm-base.nix`

- [ ] **Step 1: Add new parameters to the function signature**

Add after `sshHostKeyPath,` in the parameter attrset at the top of `vm-base.nix`:

```nix
  homeManagerModule,
  claude ? false,
  claudeConfigDir ? null,
  direnv ? true,
  extraHomeModules ? [ ],
```

- [ ] **Step 2: Add claudeShares to the let block**

Add after `sshKeyShares` definition (around line 53):

```nix
  claudeShares =
    lib.optionals (claude && claudeConfigDir != null) [
      {
        proto = "virtiofs";
        tag = "claude-config";
        source = claudeConfigDir;
        mountPoint = "/home/${userName}/.claude-host";
      }
    ];
```

- [ ] **Step 3: Add claudeShares to the shares list**

In `microvm.shares`, add `++ claudeShares` after `++ credentialShares`:

```nix
    shares =
      [
        {
          proto = "virtiofs";
          tag = "ro-store";
          source = "/nix/store";
          mountPoint = "/nix/.ro-store";
        }
      ]
      ++ sshKeyShares
      ++ workspaceShares
      ++ credentialShares
      ++ claudeShares
      ++ extraShares;
```

- [ ] **Step 4: Add home-manager import and configuration**

`vm-base.nix` currently returns a plain attrset (no existing `imports` key). Add a new `imports` key at the top of the returned attrset, plus the home-manager config. Add these after the existing `environment.systemPackages` block (before the `systemd.settings.Manager` block):

```nix
  imports = [ homeManagerModule ];

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;

  home-manager.users.${userName} = { pkgs, lib, ... }: {
    imports = extraHomeModules;

    programs.zsh.enable = true;

    programs.direnv = lib.mkIf direnv {
      enable = true;
      nix-direnv.enable = true;
    };

    home.activation.seedClaude = lib.mkIf claude (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -d "/home/${userName}/.claude" ] && [ -d "/home/${userName}/.claude-host" ]; then
          cp -a "/home/${userName}/.claude-host" "/home/${userName}/.claude"
        fi
      ''
    );

    home.stateVersion = "25.11";
  };
```

- [ ] **Step 5: Commit**

```bash
git add modules/nixos/agent-vms/vm-base.nix
git commit -m "feat(agent-vms): add home-manager integration and tool parameters to vm-base"
```

---

## Chunk 2: Module Options in default.nix

### Task 2: Add new defaults and vmSubmodule options to default.nix

**Files:**
- Modify: `modules/nixos/agent-vms/default.nix`

- [ ] **Step 1: Add new defaults options**

Add after the `defaults.hypervisor` option block (around line 150):

```nix
      claude = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Include Claude Code credential sharing in VMs by default";
      };
      claudeConfigDir = lib.mkOption {
        type = lib.types.str;
        default = "/home/${cfg.user.name}/.claude";
        description = "Host path to .claude/ directory (mounted read-only into VMs)";
      };
      direnv = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Include direnv + nix-direnv in VMs by default";
      };
```

- [ ] **Step 2: Add new vmSubmodule options**

Add after the `extraShares` option in `vmSubmodule` (around line 76):

```nix
      claude = lib.mkOption {
        type = lib.types.bool;
        default = cfg.defaults.claude;
        description = "Enable Claude Code credential sharing for this VM";
      };
      direnv = lib.mkOption {
        type = lib.types.bool;
        default = cfg.defaults.direnv;
        description = "Enable direnv + nix-direnv for this VM";
      };
      extraHomeModules = lib.mkOption {
        type = lib.types.listOf lib.types.anything;
        default = [ ];
        description = "Additional home-manager modules for the VM user";
      };
```

- [ ] **Step 3: Update mkVm to pass new parameters**

In the `mkVm` function, add the new parameters to the `vm-base.nix` call. Add after the existing `sshHostKeyPath` line:

```nix
          homeManagerModule = inputs.home-manager.nixosModules.home-manager;
          inherit (vmCfg) claude direnv extraHomeModules;
          claudeConfigDir = cfg.defaults.claudeConfigDir;
```

- [ ] **Step 4: Commit**

```bash
git add modules/nixos/agent-vms/default.nix
git commit -m "feat(agent-vms): add claude, direnv, and home-manager options to module"
```

---

## Chunk 3: CLI Flags in agent-vm.nix

### Task 3: Update agent-vm.nix with new flags and flake generation

**Files:**
- Modify: `modules/nixos/agent-vms/agent-vm.nix`

- [ ] **Step 1: Bake in homeManagerRev and new defaults**

In the `let` block at the top of the file, add after `nixpkgsRev`:

```nix
  homeManagerRev = inputs.home-manager.rev;
```

Update the function parameters — add to the `defaults` destructuring. The function already receives `defaults` from `default.nix`, so the new options are available as `defaults.claude`, `defaults.direnv`, `defaults.claudeConfigDir`.

- [ ] **Step 2: Add baked-in defaults and home-manager URL to the script**

Inside the `writeShellScriptBin` script body, add after the `NIXPKGS_URL` line:

```bash
  HOME_MANAGER_URL="github:nix-community/home-manager/${homeManagerRev}"
  DEFAULT_CLAUDE="${lib.boolToString defaults.claude}"
  DEFAULT_CLAUDE_CONFIG_DIR="${defaults.claudeConfigDir}"
  DEFAULT_DIRENV="${lib.boolToString defaults.direnv}"
```

- [ ] **Step 3: Update usage text**

Add the new flags to the usage help text, after the existing `--mem` line:

```
  --claude                        Enable Claude Code (credentials + config)
  --no-claude                     Disable Claude Code
  --direnv                        Enable direnv + nix-direnv
  --no-direnv                     Disable direnv
  --hm-module <path>              Additional home-manager module (repeatable)
```

- [ ] **Step 4: Add flag parsing in cmd_create**

Add new local variables at the top of `cmd_create`, after `local credentials=""`:

```bash
    local claude="$DEFAULT_CLAUDE"
    local use_direnv="$DEFAULT_DIRENV"
    local hm_modules=""
```

Add new cases in the `while` loop, before the `*) echo "Unknown flag"` line:

```bash
        --claude) claude="true"; shift ;;
        --no-claude) claude="false"; shift ;;
        --direnv) use_direnv="true"; shift ;;
        --no-direnv) use_direnv="false"; shift ;;
        --hm-module) hm_modules="$hm_modules $2"; shift 2 ;;
```

- [ ] **Step 5: Add hm-module file copying**

After the existing `vm-base.nix` copy block (the `sudo tee "$vm_dir/vm-base.nix"` heredoc), add:

```bash
    # Copy any extra home-manager modules into the VM directory
    local hm_imports_nix="[ ]"
    if [ -n "$hm_modules" ]; then
      hm_imports_nix="["
      for mod in $hm_modules; do
        local basename
        basename="$(basename "$mod")"
        sudo cp "$mod" "$vm_dir/$basename"
        hm_imports_nix="$hm_imports_nix (import ./$basename)"
      done
      hm_imports_nix="$hm_imports_nix ]"
    fi
```

- [ ] **Step 6: Add conflict guard for --claude + --credentials overlap**

After the hm-module copying block, add:

```bash
    # Warn if --claude and --credentials both target .claude
    if [ "$claude" = "true" ] && [ -n "$credentials" ]; then
      for cred in $credentials; do
        local cred_src="''${cred%%:*}"
        if [ "$cred_src" = "$DEFAULT_CLAUDE_CONFIG_DIR" ]; then
          echo "Warning: --claude already mounts $DEFAULT_CLAUDE_CONFIG_DIR; skipping duplicate --credentials entry" >&2
          credentials="$(echo "$credentials" | sed "s| $cred||")"
        fi
      done
    fi
```

- [ ] **Step 7: Build claude config Nix expression**

After the conflict guard block, add:

```bash
    # Build claude config dir Nix expression
    local claude_config_nix="null"
    if [ "$claude" = "true" ]; then
      claude_config_nix="\"$DEFAULT_CLAUDE_CONFIG_DIR\""
    fi
```

- [ ] **Step 8: Update the generated flake.nix**

In the `<<FLAKE` heredoc, make these changes. **Keep all existing parameters intact** — only add new lines after the existing `sshHostKeyPath` parameter:

**Add home-manager input** after the microvm input block:

```nix
    home-manager = {
      url = "$HOME_MANAGER_URL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
```

**Add `home-manager` to the outputs function arguments:**

```nix
  outputs = { self, nixpkgs, microvm, home-manager, ... }:
```

**Add new parameters to the vm-base.nix call**, after `sshHostKeyPath`:

```nix
          homeManagerModule = home-manager.nixosModules.home-manager;
          claude = $claude;
          claudeConfigDir = $claude_config_nix;
          direnv = $use_direnv;
          extraHomeModules = $hm_imports_nix;
```

- [ ] **Step 9: Commit**

```bash
git add modules/nixos/agent-vms/agent-vm.nix
git commit -m "feat(agent-vms): add --claude, --direnv, --hm-module CLI flags"
```

---

## Chunk 4: Verification and Fix the Existing Escape Bug

### Task 4: Verify the `\''${system}` escape fix is correct

**Files:**
- Verify: `modules/nixos/agent-vms/agent-vm.nix:218`

- [ ] **Step 1: Confirm the escape produces correct output**

The line should read:
```nix
    packages.\''${system}.default = self.nixosConfigurations.$name.config.microvm.declaredRunner;
```

This produces `\${system}` in the bash script, which the unquoted heredoc outputs as literal `${system}` in the generated flake.nix.

Run: Visually inspect the line in the file to confirm it's correct.

- [ ] **Step 2: Test a dry-run build of the module**

On a host with the module enabled, verify the NixOS config evaluates without errors:

```bash
nix eval .#nixosConfigurations.ada.config.system.build.toplevel --no-build 2>&1 | head -20
```

Expected: No evaluation errors (or a derivation path).

- [ ] **Step 3: Commit if any fixes were needed**

Only commit if changes were made. Otherwise skip.

### Task 5: End-to-end test on host

- [ ] **Step 1: Rebuild NixOS**

```bash
sudo nixos-rebuild switch --flake .
```

- [ ] **Step 2: Test basic VM creation (no new flags)**

```bash
agent-vm create test-basic --workspace ~/src/dotfiles
agent-vm start test-basic
agent-vm ssh test-basic -- echo "hello from VM"
agent-vm destroy test-basic
```

Expected: VM creates, starts, responds to SSH, and is destroyed cleanly.

- [ ] **Step 3: Test with --claude flag**

```bash
agent-vm create test-claude --workspace ~/src/dotfiles --claude
agent-vm start test-claude
agent-vm ssh test-claude -- ls -la ~/.claude
agent-vm destroy test-claude
```

Expected: `~/.claude` directory exists inside the VM, seeded from host.

- [ ] **Step 4: Test with --no-direnv flag**

```bash
agent-vm create test-nodirenv --workspace ~/src/dotfiles --no-direnv
agent-vm start test-nodirenv
agent-vm ssh test-nodirenv -- which direnv
agent-vm destroy test-nodirenv
```

Expected: `direnv` command not found (since direnv was disabled).

- [ ] **Step 5: Test with --direnv (default)**

```bash
agent-vm create test-direnv --workspace ~/src/dotfiles
agent-vm start test-direnv
agent-vm ssh test-direnv -- "direnv version && echo 'direnv OK'"
agent-vm destroy test-direnv
```

Expected: direnv is installed and reports its version.

- [ ] **Step 6: Commit any fixes discovered during testing**
