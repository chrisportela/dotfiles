# Agent VMs — Design Spec

## Motivation

Run coding agents (claude-code, opencode, Cursor SSH remote) in ephemeral, isolated microVMs so they can operate with full permissions without risking host data. Inspired by [Michael Stapelberg's coding agent microVM setup](https://michael.stapelberg.ch/posts/2026-02-01-coding-agent-microvm-nix/).

Key differences from the article:
- No emacs — Cursor SSH remoting, opencode, and claude-code are the target editors/agents
- Ad-hoc VMs are the primary workflow (no NixOS rebuild required)
- Declarative VMs are supported but optional
- Configurable per-VM: credentials, persistence, resources, workspace sharing

## Architecture

Two layers:

1. **Host NixOS module** (`chrisportela.agent-vms`) — sets up bridge networking, NAT, and microvm host support
2. **Ad-hoc CLI tool** (`agent-vm`) — creates/manages imperative microVMs from a shared base template

Both declarative and ad-hoc VMs use the same base VM module for consistent behavior.

## Host Infrastructure Module

**File:** `modules/nixos/agent-vms/default.nix`
**Namespace:** `chrisportela.agent-vms`

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable agent VM host support |
| `bridge.name` | str | `"microbr"` | Bridge device name |
| `bridge.subnet` | str | `"192.168.83.1/24"` | Bridge subnet (host gets .1) |
| `nat.externalInterface` | str | (required) | Host interface to NAT through |
| `defaults.vcpu` | int | `8` | Default vCPUs per VM |
| `defaults.mem` | int | `4096` | Default RAM in MB per VM |
| `defaults.hypervisor` | str | `"cloud-hypervisor"` | Default hypervisor |
| `user.name` | str | `"cmp"` | Username inside VMs |
| `user.uid` | int | `1000` | UID inside VMs |
| `user.gid` | int | `1000` | GID inside VMs |
| `user.authorizedKeys` | list of str | `[]` | SSH authorized keys for VM user |
| `vms` | attrsOf submodule | `{}` | Declarative VM definitions (optional) |

### What `enable = true` does

- Imports `microvm.nixosModules.host` (hosts that previously imported this directly, like flamme, must remove their direct import to avoid duplication)
- Creates bridge network device (`microbr`)
- Assigns host IP on the bridge subnet
- Configures TAP interface auto-bridging for microvm TAP devices
- Enables NAT from bridge to external interface
- Trusts the bridge interface in the firewall
- Adds the `agent-vm` CLI tool to system packages

### Integration into module system

The module directory `./agent-vms` is added to both:
- `modules/nixos/default.nix` — the attrset registry (`agent-vms = ./agent-vms;`)
- `modules/nixos/all.nix` — the imports list (`./agent-vms`)

Flamme's direct `inputs.microvm.nixosModules.host` import in `hosts/nixos/flamme/default.nix` must be removed and replaced with `chrisportela.agent-vms.enable = true`.

## Declarative VM Definitions

Optional. For long-lived VMs managed by NixOS config.

### Per-VM Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `ipAddress` | str | (required) | Static IP on the bridge subnet |
| `mac` | str | (required) | MAC address |
| `workspace` | nullOr path | `null` | Host directory to share via virtiofs |
| `autostart` | bool | `false` | Start VM on boot |
| `packages` | list of package | `[]` | Additional packages in VM |
| `credentials` | list of {source: str, mountPoint: str} | `[]` | Credential directories (mounted read-only) |
| `vcpu` | int | `defaults.vcpu` | vCPUs |
| `mem` | int | `defaults.mem` | RAM in MB |
| `varSize` | int | `8192` | /var volume size in MB |
| `extraShares` | list of share | `[]` | Additional virtiofs mounts |

Each entry generates a `microvm.vms.<name>` configuration using the base VM module.

### SSH host key generation for declarative VMs

Declarative VMs store SSH host keys at `/var/lib/microvms/<name>/ssh-host-keys/`. The host module includes an activation script that generates missing SSH host keys automatically (via `ssh-keygen -t ed25519`) for any declared VM that doesn't yet have them.

## Base VM Module

**File:** `modules/nixos/agent-vms/vm-base.nix`

A function that takes an attrset of parameters and returns a NixOS module. This is a standard Nix pattern — not a NixOS module with options, but a function producing one:

```nix
# vm-base.nix
{ hostName, ipAddress, mac, gatewayAddress, vcpu, mem, ... }:
{ config, lib, pkgs, ... }:
{
  # NixOS configuration using the closed-over parameters
  networking.hostName = hostName;
  microvm.vcpu = vcpu;
  # ...
}
```

Declarative VMs call this function in `default.nix` with parameters derived from the module options. Ad-hoc VM flakes call it with parameters baked into the generated `flake.nix`.

### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `hostName` | str | VM hostname |
| `ipAddress` | str | Static IP on bridge subnet |
| `mac` | str | MAC address |
| `gatewayAddress` | str | Bridge host IP (e.g., `"192.168.83.1"`) |
| `vcpu` | int | vCPU count |
| `mem` | int | RAM in MB |
| `hypervisor` | str | Hypervisor to use |
| `workspace` | nullOr str | Host path to share, or null |
| `credentials` | list of {source: str, mountPoint: str} | Read-only credential shares |
| `packages` | list of package | Extra system packages (ad-hoc flakes resolve string attr names to packages in the generated flake before calling vm-base) |
| `userName` | str | VM username |
| `uid` | int | User UID |
| `gid` | int | User GID |
| `authorizedKeys` | list of str | SSH authorized keys |
| `varSize` | int | /var volume image size in MB |
| `extraShares` | list of virtiofs share attrsets | Additional mounts |
| `sshHostKeyPath` | str | Path on host to SSH host keys directory |

### What it configures

**Hypervisor:**
- cloud-hypervisor (or configured alternative) with specified vCPU/mem
- Control socket enabled

**Networking:**
- systemd-networkd with static IP, gateway to bridge host
- DNS: 8.8.8.8, 1.1.1.1
- Firewall disabled (behind host NAT)

**Filesystem:**
- Read-only virtiofs share of `/nix/store` from host
- Writable tmpfs overlay at `/nix/.rw-store`
- `/var` volume image (configurable size) for persistent state
- Optional workspace virtiofs share
- Optional credential virtiofs shares (read-only)
- SSH host keys shared from host via read-only virtiofs

**SSH:**
- openssh enabled
- Host keys read from virtiofs-mounted `sshHostKeyPath`

**User:**
- User matching host config (name, uid, gid)
- Passwordless sudo
- Authorized SSH keys from host config
- Zsh as default shell

**Packages:**
- Base: git, ripgrep, curl, fd, jq
- Plus per-VM `packages` list

**Systemd:**
- Fast shutdown timeout (5s)
- Nix store mount ordering fix (prevents deadlock on shutdown, per microvm.nix issue #170)

## Ad-hoc CLI Tool

**File:** `modules/nixos/agent-vms/agent-vm.nix`
**Binary name:** `agent-vm`

A shell script packaged as a Nix derivation. Added to `environment.systemPackages` when the module is enabled.

### Commands

| Command | Description |
|---------|-------------|
| `agent-vm create <name> [flags]` | Scaffold a flake in `/var/lib/microvms/<name>/`, assign next IP, generate SSH host keys |
| `agent-vm start <name>` | `sudo systemctl start microvm@<name>` |
| `agent-vm stop <name>` | `sudo systemctl stop microvm@<name>` |
| `agent-vm destroy <name>` | Stop VM and remove `/var/lib/microvms/<name>/` |
| `agent-vm list` | Show existing VMs with status (running/stopped) and IP |
| `agent-vm ssh <name>` | SSH into the VM using its assigned IP |

### Create Flags

| Flag | Description |
|------|-------------|
| `--workspace <path>` | Host directory to share (optional; if omitted, no workspace is shared) |
| `--packages <pkg1,pkg2,...>` | Additional nixpkgs attr names to include |
| `--credentials <source:mountPoint>` | Credential share (repeatable). Colon-separated, parsed into `{source, mountPoint}` in the generated flake |
| `--vcpu <n>` | Override default vCPUs |
| `--mem <n>` | Override default RAM |

### How `create` works

1. Determines the next available IP by scanning existing VMs in `/var/lib/microvms/` AND reading a config file at `/var/lib/microvms/.declarative-ips` (written by the NixOS module activation script, listing IPs reserved by declarative VMs) to avoid collisions
2. Generates a deterministic MAC address from the IP (e.g., `02:00:00:00:00:XX` where XX derives from the last octet)
3. Creates `/var/lib/microvms/<name>/` directory
4. Generates SSH host keys (`ssh-keygen -t ed25519`) into `/var/lib/microvms/<name>/ssh-host-keys/`
5. Writes a `flake.nix` that:
   - Uses the same nixpkgs URL and hash as the host system (extracted from `/etc/nixos/flake.lock` or baked into the script at build time)
   - Fetches `microvm.nix` from GitHub with the same version the host uses (URL and hash baked into the script at module build time from `inputs.microvm`)
   - Copies `vm-base.nix` inline into the flake directory (so the flake is self-contained — no reference back to the dotfiles repo)
   - Calls the `vm-base` function with the specified parameters
6. Resulting flake is a real file — can be hand-edited for advanced use cases

### IP Assignment

IPs are assigned sequentially starting from `.2` on the configured subnet. The `create` command checks both:
- Existing ad-hoc VM directories in `/var/lib/microvms/` (by reading their flake configs)
- Declarative VM IPs from `/var/lib/microvms/.declarative-ips`

This prevents IP collisions between declarative and ad-hoc VMs.

## File Layout

```
modules/nixos/agent-vms/
├── default.nix          # Host module (bridge, NAT, options, declarative VMs)
├── vm-base.nix          # Shared VM configuration function
└── agent-vm.nix         # CLI script derivation
```

Added to both `modules/nixos/default.nix` (attrset) and `modules/nixos/all.nix` (imports list).

Hosts opt in with:

```nix
chrisportela.agent-vms = {
  enable = true;
  nat.externalInterface = "eno1";
  user.authorizedKeys = [ "ssh-ed25519 AAAA..." ];
};
```

## Usage Examples

### Ad-hoc (primary workflow)

```bash
# Create a VM for a project
agent-vm create myproject --workspace ~/src/myproject \
  --credentials "/home/cmp/agent-creds/claude:/home/cmp/.config/claude"

# Start and connect
agent-vm start myproject
agent-vm ssh myproject

# Inside VM: run agents with full permissions safely
claude --dangerously-skip-permissions

# Done — tear it down
agent-vm stop myproject
agent-vm destroy myproject
```

### Declarative (for persistent setups)

```nix
chrisportela.agent-vms = {
  enable = true;
  nat.externalInterface = "eno1";
  vms.infra = {
    ipAddress = "192.168.83.10";
    mac = "02:00:00:00:00:10";
    workspace = "/home/cmp/src/infra";
    packages = with pkgs; [ terraform kubectl ];
    credentials = [
      { source = "/home/cmp/agent-creds/claude"; mountPoint = "/home/cmp/.config/claude"; }
    ];
  };
};
```

## Non-Goals

- GUI/desktop inside VMs (headless only, connect via SSH)
- Tailscale inside VMs (can be added per-VM manually if needed)
- Automatic agent installation inside VMs (use credential shares + SSH to run agents)
