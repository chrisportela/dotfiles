# Agent VMs — Tool Defaults & Home Manager Design Spec

## Motivation

Currently, setting up tools like Claude Code inside an agent VM requires manually passing credential mounts and packages via `--credentials` and `--packages` flags. This is tedious and error-prone. We want per-tool flags (`--claude`, `--direnv`) that bundle the right packages, credentials, and configuration, with module-level defaults so hosts can opt in once.

Additionally, user-level configuration (shell hooks, direnv setup, dotfiles) is better managed by home-manager than raw NixOS options. Adding home-manager to the VM base gives us proper user environment management.

## Design Decisions

- **Per-tool boolean flags** over a presets system (simpler, two tools don't warrant abstraction)
- **Module defaults + CLI overrides** (`defaults.claude = true` means all VMs get it; `--no-claude` overrides)
- **Home-manager for user config** with `useGlobalPkgs = true` and `useUserPackages = true` to avoid duplicate nixpkgs eval
- **Claude credentials: read-only share + copy-on-first-boot** — host `~/.claude/` mounted read-only, seeded into a writable per-VM copy on first login

## New Module Options

Under `chrisportela.agent-vms.defaults`:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `claude` | bool | `false` | Include Claude Code in VMs by default |
| `claudeConfigDir` | str | `"/home/<user>/.claude"` | Host path to `.claude/` directory (mounted read-only into VMs) |
| `direnv` | bool | `true` | Include direnv + nix-direnv in VMs by default |

These also appear in the `vmSubmodule` for declarative VMs, defaulting to the module-level values.

## New CLI Flags

Added to `agent-vm create`:

| Flag | Description |
|------|-------------|
| `--claude` | Enable Claude Code (package + credentials + config) |
| `--no-claude` | Disable Claude Code (overrides module default) |
| `--direnv` | Enable direnv + nix-direnv |
| `--no-direnv` | Disable direnv (overrides module default) |
| `--hm-module <path>` | Additional home-manager module file to include |

Precedence: CLI flag > module default. If neither `--claude` nor `--no-claude` is passed, `defaults.claude` applies.

## What Each Flag Does

### `--claude`

1. **Package:** `claude-code` added to `environment.systemPackages`
2. **Credential mount:** Host `claudeConfigDir` (e.g., `/home/cmp/.claude/`) mounted read-only via virtiofs at `/home/<user>/.claude-host`
3. **Seed on first boot:** Activation/tmpfiles copies `.claude-host` → `~/.claude/` if `~/.claude/` doesn't exist, giving the VM a writable copy seeded from the host's auth tokens
4. **Result:** `claude` works immediately on first SSH into the VM

### `--direnv`

1. **Packages:** `direnv` and `nix-direnv` added via home-manager
2. **Shell hook:** `programs.direnv.enable = true` in home-manager configures zsh integration automatically
3. **nix-direnv:** `programs.direnv.nix-direnv.enable = true` in home-manager
4. **Result:** `cd`-ing into a workspace with `.envrc` activates the nix environment automatically

## Home Manager Integration

### Flake Input

`home-manager` added as a third flake input alongside `nixpkgs` and `microvm`, pinned by rev from the host's `inputs.home-manager.rev` (baked into the CLI script at build time, same pattern as the other inputs).

### vm-base.nix Changes

New parameters:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `claude` | `false` | Enable Claude Code |
| `claudeConfigDir` | `null` | Host path to `.claude/` (when claude is enabled) |
| `direnv` | `true` | Enable direnv + nix-direnv |
| `extraHomeModules` | `[]` | Additional home-manager modules for the VM user |

Configuration added:

```nix
imports = [ home-manager.nixosModules.home-manager ];

home-manager.useGlobalPkgs = true;
home-manager.useUserPackages = true;

home-manager.users.<userName> = { pkgs, ... }: {
  imports = extraHomeModules;

  programs.zsh.enable = true;

  # When direnv enabled:
  programs.direnv = {
    enable = true;       # direnv flag
    nix-direnv.enable = true;
  };

  # When claude enabled:
  # Seed ~/.claude from read-only mount on first use
  home.activation.seedClaude = lib.mkIf claude (
    lib.hm.dag.entryAfter ["writeBoundary"] ''
      if [ ! -d "$HOME/.claude" ] && [ -d "$HOME/.claude-host" ]; then
        cp -a "$HOME/.claude-host" "$HOME/.claude"
      fi
    ''
  );

  home.stateVersion = "25.11";
};
```

### Virtiofs Shares (when claude enabled)

```nix
claudeShares = lib.optionals claude [
  {
    proto = "virtiofs";
    tag = "claude-config";
    source = claudeConfigDir;
    mountPoint = "/home/${userName}/.claude-host";
  }
];
```

### Declarative VM Submodule

New options in `vmSubmodule`:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `claude` | bool | `defaults.claude` | Enable Claude Code for this VM |
| `direnv` | bool | `defaults.direnv` | Enable direnv for this VM |
| `extraHomeModules` | list of path | `[]` | Additional home-manager modules |

### Ad-hoc Flake Generation

The generated `flake.nix` gains:
- `home-manager` input (pinned rev)
- `claude`, `claudeConfigDir`, `direnv` parameters passed to `vm-base.nix`
- `home-manager.nixosModules.home-manager` in the module imports (passed via vm-base.nix or directly)

## Files Changed

| File | Changes |
|------|---------|
| `default.nix` | New `defaults.claude`, `defaults.claudeConfigDir`, `defaults.direnv` options. New vmSubmodule options. Pass `inputs.home-manager` to agent-vm.nix. |
| `agent-vm.nix` | Bake `homeManagerRev`. New CLI flags. Generate flake with home-manager input. Pass claude/direnv booleans to vm-base.nix. Handle `--hm-module` file copy. |
| `vm-base.nix` | New parameters. Import home-manager NixOS module. Define `home-manager.users.<user>` config. Conditional claude shares + seed activation. Conditional direnv config. |

## Usage Examples

### Ad-hoc with Claude Code

```bash
# Claude Code ready out of the box
agent-vm create myproject --workspace ~/src/myproject --claude
agent-vm start myproject
agent-vm ssh myproject
# Inside VM: claude just works
claude --dangerously-skip-permissions
```

### Ad-hoc with everything disabled

```bash
agent-vm create minimal --workspace ~/src/minimal --no-direnv
```

### Host default: always include Claude

```nix
chrisportela.agent-vms = {
  enable = true;
  nat.externalInterface = "eno1";
  defaults.claude = true;
  user.authorizedKeys = [ "ssh-ed25519 AAAA..." ];
};
```

Now `agent-vm create foo --workspace ~/src/foo` includes Claude Code automatically. Use `--no-claude` to opt out.

### Custom home-manager config

```bash
agent-vm create myproject --workspace ~/src/myproject --claude --hm-module ./my-hm.nix
```

## Non-Goals

- Passing through the host's full home-manager config (too complex, too many host dependencies)
- Managing multiple users inside a VM (single-user VMs only)
- Auto-updating Claude credentials from host to running VMs (recreate the VM instead)
