# ada Memory Tuning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `vm.overcommit_memory=2` with cgroup-based memory protection on the ada NixOS host, switch from zram to zswap over the existing Optane swap, and consolidate the cgroup containment + critical-service hardening into a reusable `chrisportela.memory-protection` module.

**Architecture:** Four-layer protection — (1) zswap+Optane swap, (2) per-cgroup `MemoryMax`/`MemoryHigh` ceilings on `nix-daemon`, `docker.slice`, `user.slice`, (3) `systemd-oomd` PSI-based pre-OOM, (4) `OOMScoreAdjust` + `MemoryMin` hardening on critical services (dbus, journald, sshd, systemd-logind, NetworkManager, tailscaled). Layers 2 and 4 live in a new `modules/nixos/memory-protection/` module; layers 1 and 3 stay in the host file because they encode hardware-specific assumptions.

**Tech Stack:** NixOS modules (Nix), systemd cgroup v2, systemd-oomd, zswap kernel feature, Linux VM sysctls.

**Spec reference:** `docs/superpowers/specs/2026-04-29-ada-memory-tuning-design.md`

**Migration safety:** Tasks 5–7 land all changes *except* the final overcommit-mode flip. During that window `vm.overcommit_memory=2` is retained but `overcommit_ratio` is raised to 250 so legitimate builds succeed and cgroup containment can be witnessed under load. Task 9 performs the final cutover after Task 8's manual validation.

---

## File structure

**Create:**
- `modules/nixos/memory-protection/default.nix` — module options + implementation
- `modules/nixos/memory-protection/README.md` — purpose, options, dependencies, gotchas

**Modify:**
- `modules/nixos/default.nix` — add `memory-protection` entry to attrset
- `modules/nixos/all.nix` — add `./memory-protection` to imports list
- `hosts/nixos/ada/hardware.nix` — replace inline sysctls (lines 73–85), zramSwap block (lines 87–92), `systemd.oomd` (lines 97–102), inline `dbus`/`journald` `ManagedOOMPreference` (lines 105–106), `nix-daemon.serviceConfig` (lines 111–116); add `boot.kernelParams` for zswap; enable the new module

**Out of band:**
- `~/.claude/projects/-home-cmp-src-dotfiles/memory/feedback_overcommit_strict.md` — update content after Task 9 to reflect the new architecture

---

## Verification commands used throughout

`nix flake check` and full host builds are slow. For per-task verification we use evaluation-only checks where possible.

```bash
# Fast: evaluates the configuration without building derivations.
# Use after every Nix file change. Errors here are syntax/type errors.
nix eval --raw .#nixosConfigurations.ada.config.system.build.toplevel.drvPath

# Slower but authoritative: builds the toplevel derivation. Use before activation.
nix build .#nixosConfigurations.ada.config.system.build.toplevel --no-link
```

If a verification step is "evaluate the module produces expected config", we use targeted `nix eval`:

```bash
# Example: confirm dbus.serviceConfig.OOMScoreAdjust is set to -900
nix eval --json .#nixosConfigurations.ada.config.systemd.services.dbus.serviceConfig.OOMScoreAdjust
```

**Reminder:** New files MUST be `git add`-ed before `nix build`/`nix eval` will see them — flake evaluation excludes untracked files. Each task that creates a file includes a `git add` step before its first verification.

---

### Task 1: Create memory-protection module skeleton (options only)

**Files:**
- Create: `modules/nixos/memory-protection/default.nix`

This task creates the module with only the `options` block — the `config` block is empty. Verifies the option types are accepted by Nix before any implementation is attached.

- [ ] **Step 1: Create the module file with options only**

Create `modules/nixos/memory-protection/default.nix` with this content:

```nix
{ config, lib, ... }:

let
  cfg = config.chrisportela.memory-protection;
in
{
  options.chrisportela.memory-protection = {
    enable = lib.mkEnableOption "cgroup-based memory protection (Layer 2 + 4)";

    nixDaemon = {
      enable = lib.mkEnableOption "nix-daemon cgroup ceilings";
      memoryMax = lib.mkOption {
        type = lib.types.str;
        example = "90G";
        description = "Hard memory ceiling for nix-daemon and its build children.";
      };
      memoryHigh = lib.mkOption {
        type = lib.types.str;
        example = "75G";
        description = "Soft memory threshold; reclaim/pressure starts here.";
      };
    };

    dockerSlice = {
      enable = lib.mkEnableOption "docker.slice with cgroup ceilings (covers docker daemon + all containers)";
      memoryMax = lib.mkOption {
        type = lib.types.str;
        example = "90G";
        description = "Hard memory ceiling for the entire docker.slice.";
      };
      memoryHigh = lib.mkOption {
        type = lib.types.str;
        example = "75G";
        description = "Soft memory threshold; reclaim/pressure starts here.";
      };
    };

    userSlice = {
      enable = lib.mkEnableOption "user.slice cgroup ceilings (bounds interactive shell, KDE, browsers, games)";
      memoryMax = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "100G";
        description = "Hard memory ceiling for user.slice. Null disables the cap.";
      };
      memoryHigh = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "85G";
        description = "Soft memory threshold for user.slice. Null disables the threshold.";
      };
    };

    microvmHost = lib.mkEnableOption "host-side OOM settings for microvm@.service (biases kernel toward killing VMs before host services)";
  };

  config = lib.mkIf cfg.enable {
    # Implementation lands in subsequent tasks.
  };
}
```

- [ ] **Step 2: Stage the new file**

```bash
git add modules/nixos/memory-protection/default.nix
```

- [ ] **Step 3: Verify Nix evaluation succeeds**

The module isn't wired into the host yet (that happens in Task 4), so this just confirms the file parses:

```bash
nix-instantiate --parse modules/nixos/memory-protection/default.nix > /dev/null
```

Expected: command exits 0 with no output. Any output indicates a syntax error.

- [ ] **Step 4: Commit**

```bash
git commit -m "Add memory-protection module skeleton (options only)

Defines chrisportela.memory-protection options for cgroup-based memory
protection. Implementation follows in subsequent commits.
"
```

---

### Task 2: Implement always-on critical-service hardening

**Files:**
- Modify: `modules/nixos/memory-protection/default.nix`

Adds the unconditional layer-4 protection: `OOMScoreAdjust`, `ManagedOOMPreference`, and `MemoryMin` reservations on dbus, journald, sshd, systemd-logind. NetworkManager and tailscaled are added conditionally (only when those services are enabled by the host).

- [ ] **Step 1: Replace the empty `config` block with critical-service hardening**

In `modules/nixos/memory-protection/default.nix`, replace this:

```nix
  config = lib.mkIf cfg.enable {
    # Implementation lands in subsequent tasks.
  };
```

With this:

```nix
  config = lib.mkIf cfg.enable (lib.mkMerge [
    # Always-on: critical-service hardening
    {
      systemd.services.dbus.serviceConfig = {
        ManagedOOMPreference = "avoid";
        OOMScoreAdjust = -900;
        MemoryMin = "64M";
      };
      systemd.services.systemd-journald.serviceConfig = {
        ManagedOOMPreference = "avoid";
        OOMScoreAdjust = -900;
        MemoryMin = "128M";
      };
      systemd.services.sshd.serviceConfig = {
        ManagedOOMPreference = "avoid";
        OOMScoreAdjust = -900;
        MemoryMin = "32M";
      };
      systemd.services.systemd-logind.serviceConfig = {
        ManagedOOMPreference = "avoid";
        OOMScoreAdjust = -900;
      };
    }

    (lib.mkIf config.networking.networkmanager.enable {
      systemd.services.NetworkManager.serviceConfig = {
        ManagedOOMPreference = "avoid";
        OOMScoreAdjust = -800;
      };
    })

    (lib.mkIf config.services.tailscale.enable {
      systemd.services.tailscaled.serviceConfig = {
        ManagedOOMPreference = "avoid";
        OOMScoreAdjust = -800;
      };
    })
  ]);
```

- [ ] **Step 2: Verify the file still parses**

```bash
nix-instantiate --parse modules/nixos/memory-protection/default.nix > /dev/null
```

Expected: exit 0, no output.

- [ ] **Step 3: Commit**

```bash
git add modules/nixos/memory-protection/default.nix
git commit -m "memory-protection: add always-on critical-service hardening

OOMScoreAdjust=-900 + ManagedOOMPreference=avoid on dbus, journald,
sshd, systemd-logind. -800 on NetworkManager and tailscaled when
those services are enabled. MemoryMin reservations protect working
sets of dbus and journald during reclaim.
"
```

---

### Task 3: Implement opt-in cgroup ceilings (nixDaemon, dockerSlice, userSlice, microvmHost)

**Files:**
- Modify: `modules/nixos/memory-protection/default.nix`

- [ ] **Step 1: Append four `lib.mkIf` blocks to the `lib.mkMerge` list**

In `modules/nixos/memory-protection/default.nix`, replace the closing `]);` of the `lib.mkMerge` with the four new blocks followed by `]);`. The function-end region should now look like this:

```nix
    (lib.mkIf config.services.tailscale.enable {
      systemd.services.tailscaled.serviceConfig = {
        ManagedOOMPreference = "avoid";
        OOMScoreAdjust = -800;
      };
    })

    # nix-daemon ceiling (opt-in via nixDaemon.enable)
    (lib.mkIf cfg.nixDaemon.enable {
      systemd.services.nix-daemon.serviceConfig = {
        ManagedOOMMemoryPressure = "kill";
        ManagedOOMMemoryPressureLimit = "80%";
        MemoryMax = cfg.nixDaemon.memoryMax;
        MemoryHigh = cfg.nixDaemon.memoryHigh;
      };
    })

    # docker.slice (opt-in via dockerSlice.enable)
    (lib.mkIf cfg.dockerSlice.enable {
      systemd.services.docker.serviceConfig.Slice = "docker.slice";
      systemd.slices."docker".sliceConfig = {
        MemoryMax = cfg.dockerSlice.memoryMax;
        MemoryHigh = cfg.dockerSlice.memoryHigh;
        ManagedOOMMemoryPressure = "kill";
        ManagedOOMMemoryPressureLimit = "80%";
      };
      virtualisation.docker.daemon.settings = {
        "exec-opts" = [ "native.cgroupdriver=systemd" ];
        "cgroup-parent" = "docker.slice";
      };
    })

    # user.slice (opt-in via userSlice.enable; nullable values disable)
    (lib.mkIf (cfg.userSlice.enable && cfg.userSlice.memoryMax != null && cfg.userSlice.memoryHigh != null) {
      systemd.slices."user".sliceConfig = {
        MemoryMax = cfg.userSlice.memoryMax;
        MemoryHigh = cfg.userSlice.memoryHigh;
        ManagedOOMMemoryPressure = "kill";
        ManagedOOMMemoryPressureLimit = "80%";
      };
    })

    # microvm@.service host-side OOM (opt-in via microvmHost)
    (lib.mkIf cfg.microvmHost {
      systemd.services."microvm@".serviceConfig = {
        OOMScoreAdjust = 200;
        ManagedOOMPreference = "omit";
      };
    })
  ]);
```

- [ ] **Step 2: Verify file parses**

```bash
nix-instantiate --parse modules/nixos/memory-protection/default.nix > /dev/null
```

Expected: exit 0, no output.

- [ ] **Step 3: Commit**

```bash
git add modules/nixos/memory-protection/default.nix
git commit -m "memory-protection: add opt-in cgroup ceilings

Per-host opt-in implementations for nix-daemon ceiling, docker.slice
(daemon + containers via cgroup-parent), user.slice cap, and
microvm@.service OOM bias.
"
```

---

### Task 4: Write README for the module

**Files:**
- Create: `modules/nixos/memory-protection/README.md`

CLAUDE.md requires every module to ship with a README documenting purpose, options, and dependencies.

- [ ] **Step 1: Create the README**

Create `modules/nixos/memory-protection/README.md` with this content:

```markdown
# Memory Protection Module

Cgroup-based memory protection for NixOS hosts. Implements two of the four layers in a host's overall memory-pressure protection strategy:

- **Layer 2 (cgroup ceilings):** `MemoryMax` / `MemoryHigh` on `nix-daemon`, `docker.slice`, and `user.slice`. A runaway in any cgroup is contained inside that cgroup.
- **Layer 4 (critical-service hardening):** `OOMScoreAdjust` + `ManagedOOMPreference=avoid` + `MemoryMin` on dbus, journald, sshd, systemd-logind, NetworkManager, tailscaled. Biases the kernel OOM killer (and systemd-oomd) away from critical services.

Layer 1 (swap + zswap configuration) and Layer 3 (`systemd.oomd` settings) live in the host file because they encode hardware-specific assumptions about RAM size, swap medium, and ZFS/ARC interaction.

## Options

All options under `chrisportela.memory-protection`:

- `enable` — Enable the module. Always-on critical-service hardening kicks in.
- `nixDaemon.enable` — Enable cgroup ceilings on `nix-daemon.service`.
- `nixDaemon.memoryMax` — Hard ceiling string (e.g., `"90G"`, `"14G"`).
- `nixDaemon.memoryHigh` — Soft pressure threshold string.
- `dockerSlice.enable` — Move `docker.service` into `docker.slice` and apply ceilings to the slice (covers daemon + all containers).
- `dockerSlice.memoryMax` / `memoryHigh` — Slice-level ceiling/threshold.
- `userSlice.enable` — Bound `user.slice` (interactive sessions: shell, KDE, browsers, games).
- `userSlice.memoryMax` / `memoryHigh` — Nullable; both must be set for the cap to apply.
- `microvmHost` — Apply host-side OOM settings to `microvm@.service` so the kernel prefers killing whole VMs over host services in a memory crisis.

## Dependencies

- `systemd` cgroup v2 (NixOS default since 23.05) — required for `MemoryMin` reservations to be effective.
- `systemd-oomd` should be enabled by the host (`systemd.oomd.enable = true`). The module does not enable it; `ManagedOOM*` directives only do anything if oomd is running.
- `dockerSlice.enable = true` requires `virtualisation.docker.enable = true`. Otherwise `docker.slice` is created but unused.
- `microvmHost = true` requires `microvm.nix` integration (the host imports `inputs.microvm.nixosModules.host`).

## Gotchas

- **`user.slice` caps affect the entire interactive session** — including KDE Plasma, browsers, games, and `nix develop` shells. Set generously; a runaway in *any* user process counts against the cap.
- **`docker.slice` requires the systemd cgroup driver.** The module configures `daemon.json` accordingly. If a host had docker configured with `cgroup-driver=cgroupfs`, switching may require a docker daemon restart and may invalidate cached image metadata.
- **Critical-service hardening uses `OOMScoreAdjust=-900`, not `-1000`.** -1000 disables the OOM killer for the PID entirely, which is risky if the service itself runs away. -900 strongly biases against killing while still allowing it as a last resort.
- **`MemoryMin` is a reservation, not a request.** Pages held by services with `MemoryMin` are reclaimed last under pressure, leaving their working sets alone. Effective only with cgroup v2.

## Example: ada (large workstation)

```nix
chrisportela.memory-protection = {
  enable = true;
  nixDaemon = { enable = true; memoryMax = "90G"; memoryHigh = "75G"; };
  dockerSlice = { enable = true; memoryMax = "90G"; memoryHigh = "75G"; };
  userSlice = { enable = true; memoryMax = "100G"; memoryHigh = "85G"; };
  microvmHost = true;
};
```

## Example: smaller host (e.g., flamme, 16GB)

```nix
chrisportela.memory-protection = {
  enable = true;
  nixDaemon = { enable = true; memoryMax = "14G"; memoryHigh = "12G"; };
};
```
```

- [ ] **Step 2: Stage and commit**

```bash
git add modules/nixos/memory-protection/README.md
git commit -m "memory-protection: add module README"
```

---

### Task 5: Register module in aggregator

**Files:**
- Modify: `modules/nixos/default.nix`
- Modify: `modules/nixos/all.nix`

Until this task, the module exists but isn't wired into any host. After this task, every NixOS host that imports `self.nixosModules.default` (which is all of them per `flake.nix:311`) gets the new options available — but the options remain inert until a host enables the module.

- [ ] **Step 1: Add entry to `modules/nixos/default.nix`**

In `modules/nixos/default.nix`, the file currently looks like this:

```nix
{
  agent-vms = ./agent-vms;
  cafecitocloud = ./cafecitocloud;
  common = ./common.nix;
  # ddc = ./ddc.nix;
  local-llm = ./local-llm;
  gaming = ./gaming.nix;
  network = ./network.nix;
  nixpkgs = ./nixpkgs.nix;
  nginx-cloudflare = ./nginx-cloudflare.nix;
  openssh = ./openssh.nix;
  ftp = ./ftp.nix;
  # Single module that imports all of the above; use this in host configs.
  default = ./all.nix;
}
```

Change to (added line is `memory-protection = ./memory-protection;`, alphabetized):

```nix
{
  agent-vms = ./agent-vms;
  cafecitocloud = ./cafecitocloud;
  common = ./common.nix;
  # ddc = ./ddc.nix;
  local-llm = ./local-llm;
  gaming = ./gaming.nix;
  memory-protection = ./memory-protection;
  network = ./network.nix;
  nixpkgs = ./nixpkgs.nix;
  nginx-cloudflare = ./nginx-cloudflare.nix;
  openssh = ./openssh.nix;
  ftp = ./ftp.nix;
  # Single module that imports all of the above; use this in host configs.
  default = ./all.nix;
}
```

- [ ] **Step 2: Add to imports in `modules/nixos/all.nix`**

The current file:

```nix
# Aggregator: import all NixOS modules. Each module is toggled via its enable option.
{ ... }:
{
  imports = [
    ./agent-vms
    ./nixpkgs.nix
    ./common.nix
    ./network.nix
    ./openssh.nix
    ./gaming.nix
    ./ftp.nix
    ./cafecitocloud
    ./local-llm
    ./nginx-cloudflare.nix
    ./samba
  ];
}
```

Change to:

```nix
# Aggregator: import all NixOS modules. Each module is toggled via its enable option.
{ ... }:
{
  imports = [
    ./agent-vms
    ./nixpkgs.nix
    ./common.nix
    ./network.nix
    ./openssh.nix
    ./gaming.nix
    ./ftp.nix
    ./cafecitocloud
    ./local-llm
    ./memory-protection
    ./nginx-cloudflare.nix
    ./samba
  ];
}
```

- [ ] **Step 3: Verify ada's config still evaluates with the module loaded but unused**

```bash
nix eval --raw .#nixosConfigurations.ada.config.system.build.toplevel.drvPath > /dev/null
```

Expected: exit 0. The output (a `/nix/store/...drv` path) confirms evaluation succeeded with the new module loaded. No behavior change yet because no host has enabled it.

- [ ] **Step 4: Verify the module is reachable in the option tree**

```bash
nix eval --json .#nixosConfigurations.ada.options.chrisportela.memory-protection.enable.description
```

Expected: a JSON string containing `"cgroup-based memory protection (Layer 2 + 4)"`. Failure = the module wasn't imported correctly.

- [ ] **Step 5: Commit**

```bash
git add modules/nixos/default.nix modules/nixos/all.nix
git commit -m "Register memory-protection module in nixos aggregator"
```

---

### Task 6: Update ada Layer 1 (sysctls + zswap, validation mode)

**Files:**
- Modify: `hosts/nixos/ada/hardware.nix:73-92`

Updates the sysctl block to drop `vm.swappiness=133` (the zram-tuned value), add three new sysctls, and **keep `vm.overcommit_memory=2` with `overcommit_ratio=250`** so commit budget is wide enough for sci-python builds during validation. Disables zramSwap, adds zswap kernel parameters.

The final cutover to `vm.overcommit_memory=0` happens in Task 9.

- [ ] **Step 1: Replace the sysctl block**

In `hosts/nixos/ada/hardware.nix`, find this block (currently lines 73–85):

```nix
  boot.kernel.sysctl = {
    "vm.swappiness" = 133;

    # Overcommit mode 2: strict accounting. malloc fails with ENOMEM instead of
    # letting the system exhaust all memory and having the kernel OOM-kill
    # critical services (systemd, dbus, tmux). Commit limit formula:
    #   swap + (overcommit_ratio% × RAM)
    # With 64G RAM, 64G swap, 32G zram, ratio=95:
    #   ~157G virtual memory budget — plenty for normal use, but CUDA builds
    #   that would have OOM'd the whole system now just fail their allocation.
    "vm.overcommit_memory" = 2;
    "vm.overcommit_ratio" = 95;
  };
```

Replace with:

```nix
  boot.kernel.sysctl = {
    # Validation phase: strict overcommit retained as a backstop while we
    # verify cgroup containment under load. Wide budget (64G swap + 250% × 64G
    # RAM ≈ 224G) lets legitimate sci-python and docker builds proceed.
    # Task 9 of the plan switches this to mode 0 once cgroup containment is
    # validated.
    "vm.overcommit_memory" = 2;
    "vm.overcommit_ratio" = 250;

    # Less aggressive than the previous 133 (which was tuned to push pages
    # into zram). With zswap+Optane, swap is fast enough that we don't need
    # to bias hard.
    "vm.swappiness" = 100;

    # Wake kswapd at ~2% free RAM (~1.3GB on 64GB) instead of the default
    # 0.1% (~64MB). Default is far too late on big-memory boxes; allocations
    # stall before reclaim catches up.
    "vm.watermark_scale_factor" = 200;

    # Bias toward keeping file cache under pressure. Default 100 reclaims
    # dentry/inode cache as aggressively as page cache; 50 keeps file cache
    # longer (helps nix-store reads + ZFS ARC interactions).
    "vm.vfs_cache_pressure" = 50;
  };
```

- [ ] **Step 2: Replace the `zramSwap` block with `zswap` kernel params**

Currently lines 87–92:

```nix
  zramSwap = {
    enable = true;
    priority = 5;
    algorithm = "zstd";
    memoryPercent = 50;
  };
```

Replace with:

```nix
  zramSwap.enable = false;

  # zswap: compressed-page pool in front of Optane swap. Hot pages stay
  # compressed in RAM (40% pool ≈ 25.6GB on 64GB), cold pages spill to
  # the 4×16GB Optane swap partitions.
  boot.kernelParams = [
    "zswap.enabled=1"
    "zswap.compressor=zstd"
    "zswap.zpool=zsmalloc"
    "zswap.max_pool_percent=40"
    "zswap.shrinker_enabled=Y"
  ];
```

- [ ] **Step 3: Verify the host config still evaluates**

```bash
nix eval --raw .#nixosConfigurations.ada.config.system.build.toplevel.drvPath > /dev/null
```

Expected: exit 0. The drv path is regenerated.

- [ ] **Step 4: Confirm zswap is in kernel params**

```bash
nix eval --json .#nixosConfigurations.ada.config.boot.kernelParams | grep -c zswap
```

Expected: `5` (five zswap.* parameters added).

- [ ] **Step 5: Commit**

```bash
git add hosts/nixos/ada/hardware.nix
git commit -m "ada: switch zram->zswap, retune sysctls (validation mode)

Disable zram, enable zswap with zstd+zsmalloc and 40% max pool.
Replace swappiness=133 with 100 (zswap+Optane is fast enough); add
watermark_scale_factor=200 and vfs_cache_pressure=50 for big-memory
behavior. Strict overcommit retained with overcommit_ratio=250 so
sci-python and docker builds succeed while cgroup containment is
validated. Task 9 switches to vm.overcommit_memory=0.
"
```

---

### Task 7: Replace ada inline cgroup config with the module

**Files:**
- Modify: `hosts/nixos/ada/hardware.nix` (the `systemd.oomd`, `ManagedOOMPreference`, and `nix-daemon.serviceConfig` regions — line numbers shifted after Task 6, so use content-based search/replace)

Replaces the existing inline `dbus`/`journald` `ManagedOOMPreference` lines and the `nix-daemon.serviceConfig` block with the new module enablement. Also updates `systemd.oomd` to add the validation-mode tuning.

- [ ] **Step 1: Replace the systemd-oomd block**

In `hosts/nixos/ada/hardware.nix`, find this block:

```nix
  systemd.oomd = {
    enable = true;
    enableRootSlice = true;
    enableUserSlices = true;
    enableSystemSlice = true;
  };
```

Replace with:

```nix
  systemd.oomd = {
    enable = true;
    enableRootSlice = true;
    enableUserSlices = true;
    enableSystemSlice = true;
    extraConfig = {
      # Default 30s is too patient on a workstation. 10s catches runaways
      # before interactive responsiveness craters.
      DefaultMemoryPressureDurationSec = "10s";
      # Act when global swap usage crosses 90%. Reaching this on Optane
      # means we've exhausted reclaim budget, not just normal cold-page
      # eviction.
      SwapUsedLimit = "90%";
    };
  };
```

- [ ] **Step 2: Remove the inline `ManagedOOMPreference` lines**

Find these lines:

```nix
  # Protect critical system services from OOM
  systemd.services.dbus.serviceConfig.ManagedOOMPreference = "avoid";
  systemd.services.systemd-journald.serviceConfig.ManagedOOMPreference = "avoid";
```

Delete them entirely. The module covers these (and adds `OOMScoreAdjust` and `MemoryMin`).

- [ ] **Step 3: Replace the inline `nix-daemon.serviceConfig` block**

Find this block:

```nix
  # Limit nix-daemon builds to prevent runaway memory consumption.
  # MemoryHigh triggers systemd-oomd to kill within this cgroup.
  # MemoryMax is a hard ceiling enforced by the kernel.
  systemd.services.nix-daemon.serviceConfig = {
    ManagedOOMMemoryPressure = "kill";
    ManagedOOMMemoryPressureLimit = "80%"; # kill when 80% pressure in this cgroup
    MemoryMax = "55G"; # hard ceiling for all nix-daemon children
    MemoryHigh = "48G"; # trigger pressure/reclaim at 48G
  };
```

Replace with the module enablement:

```nix
  # Memory protection: cgroup ceilings + critical-service hardening.
  # See modules/nixos/memory-protection/README.md for layer architecture.
  chrisportela.memory-protection = {
    enable = true;
    nixDaemon = {
      enable = true;
      memoryMax = "90G";
      memoryHigh = "75G";
    };
    dockerSlice = {
      enable = true;
      memoryMax = "90G";
      memoryHigh = "75G";
    };
    userSlice = {
      enable = true;
      memoryMax = "100G";
      memoryHigh = "85G";
    };
    microvmHost = true;
  };
```

- [ ] **Step 4: Verify host evaluation**

```bash
nix eval --raw .#nixosConfigurations.ada.config.system.build.toplevel.drvPath > /dev/null
```

Expected: exit 0.

- [ ] **Step 5: Confirm dbus, sshd, nix-daemon got the expected config**

```bash
# Critical service hardening from the module
nix eval --json .#nixosConfigurations.ada.config.systemd.services.dbus.serviceConfig.OOMScoreAdjust
# Expected: -900

nix eval --json .#nixosConfigurations.ada.config.systemd.services.sshd.serviceConfig.OOMScoreAdjust
# Expected: -900

nix eval --json .#nixosConfigurations.ada.config.systemd.services.dbus.serviceConfig.MemoryMin
# Expected: "64M"

# nix-daemon ceiling raised from 55G to 90G
nix eval --json .#nixosConfigurations.ada.config.systemd.services.nix-daemon.serviceConfig.MemoryMax
# Expected: "90G"

# docker.slice exists with limits
nix eval --json .#nixosConfigurations.ada.config.systemd.slices.docker.sliceConfig.MemoryMax
# Expected: "90G"

# user.slice limit applied
nix eval --json .#nixosConfigurations.ada.config.systemd.slices.user.sliceConfig.MemoryMax
# Expected: "100G"

# microvm@ host-side OOM bias
nix eval --json .#nixosConfigurations.ada.config.systemd.services."microvm@".serviceConfig.OOMScoreAdjust
# Expected: 200
```

Each command must return the expected value or evaluation has gone wrong — investigate before continuing.

- [ ] **Step 6: Build the toplevel to confirm no late-stage build errors**

```bash
nix build .#nixosConfigurations.ada.config.system.build.toplevel --no-link
```

Expected: builds successfully (may take several minutes; uses cached store paths where possible).

- [ ] **Step 7: Commit**

```bash
git add hosts/nixos/ada/hardware.nix
git commit -m "ada: enable memory-protection module, tune systemd-oomd

Replaces inline dbus/journald ManagedOOMPreference and nix-daemon
serviceConfig with chrisportela.memory-protection (also covers sshd,
systemd-logind, NetworkManager, tailscaled, docker.slice, user.slice,
microvm@ host OOM bias). systemd-oomd gets explicit 10s pressure
duration and 90% swap-used limit.

Strict overcommit (mode 2 with ratio=250 from previous commit) is
still active as a backstop until cgroup containment is validated.
"
```

---

### Task 8: Activate and validate under load

**Files:** No code changes. This task is manual verification.

This is the load-bearing checkpoint. If anything in the new architecture is broken, it surfaces here while strict overcommit is still active as a safety net.

- [ ] **Step 1: Apply the new configuration**

```bash
sudo nixos-rebuild switch --flake .#ada
```

Expected: rebuild succeeds; activation reports services restarted (notably docker.service if cgroup driver changed, microvm@.service may need stop/restart for OOMScoreAdjust to take effect on existing instances).

- [ ] **Step 2: Sanity-check the activated state**

Run each command and confirm the output:

```bash
# Slices created and limited
systemctl status user.slice docker.slice 2>&1 | grep -E "Memory|Active"
# Expected: "Memory: <usage>" / "Active: active" for both

# nix-daemon limits raised
systemctl show nix-daemon.service -p MemoryMax,MemoryHigh
# Expected: MemoryMax=96636764160 (90 * 1024^3), MemoryHigh=80530636800 (75 * 1024^3)

# zswap active
zcat /proc/config.gz 2>/dev/null | grep -i zswap || true  # zswap is built-in; just informational
ls /sys/module/zswap/parameters/
cat /sys/module/zswap/parameters/enabled
# Expected: Y

cat /sys/module/zswap/parameters/max_pool_percent
# Expected: 40

# zram absent + swap priorities
swapon --show
# Expected: 4 rows for /dev/dm-* (or /dev/nvme*p1) Optane partitions, NO /dev/zram0
# CHECK: the PRIO column must show the same value on all 4 rows (e.g., all -2,
# all 100, all -3 — the absolute number doesn't matter, only that they match).
# Equal priorities cause the kernel to stripe across all 4 devices, giving
# 4× IOPS for swap traffic. Mismatched priorities mean sequential fill — only
# one Optane drive does work at a time.
#
# If priorities differ, this is a follow-up to fix in a subsequent commit by
# adding an explicit `swapDevices` block in hardware.nix setting all four to
# `priority = 100`. Disko's swap content type does not always set priority
# explicitly. Not blocking for this plan — the cutover works either way, just
# slower under heavy swap.

# Critical services have OOMScoreAdjust + ManagedOOMPreference
for svc in dbus systemd-journald sshd systemd-logind; do
  echo "=== $svc ==="
  systemctl show "$svc" -p OOMScoreAdjust,ManagedOOMPreference,MemoryMin
done
# Expected: OOMScoreAdjust=-900, ManagedOOMPreference=avoid for all
# Expected: dbus MemoryMin=64M, journald MemoryMin=128M, sshd MemoryMin=32M

# systemd-oomd watching the slices
oomctl
# Expected: lists user.slice, docker.slice, system.slice, possibly system-nix\x2ddaemon.scope or similar
```

If any of these show unexpected values, stop and investigate before continuing. Mode 2 with ratio=250 is still active so the system itself is protected.

- [ ] **Step 3: Run a load test — a previously-failing build**

Run BOTH of these (a nix-daemon path and a docker path) to exercise both cgroup containment domains. They can run sequentially; running concurrently would also exercise oomd's victim-picking but isn't required:

```bash
# Path 1 — exercises the nix-daemon cgroup
nix build nixpkgs#python3Packages.scipy --no-link

# Path 2 — exercises docker.slice
docker build --tag mem-test:latest - <<'EOF'
FROM python:3.12
RUN pip install --no-cache-dir torch numpy scipy
EOF
```

If the user has a specific build that was previously failing with ENOMEM, run that as well — it's the most direct evidence the fix worked.

While each build runs, in another terminal:

```bash
# Watch which cgroup the build is in
systemd-cgls | grep -E "(docker|nix-daemon|build)" | head -20

# Watch swap usage
watch -n 2 'swapon --show; echo; cat /sys/kernel/debug/zswap/stored_pages'
```

- [ ] **Step 4: Confirm validation criteria**

After the build completes (success or failure), verify:

- [ ] Build either completed successfully OR was killed within its own cgroup (not via the kernel OOM killer, not by killing system services).
- [ ] `journalctl --since "1 hour ago" -u dbus -u sshd -u systemd-journald -u systemd-logind` shows no kills or unexpected restarts of these services.
- [ ] `journalctl --since "1 hour ago" -u systemd-oomd` shows oomd activity (it should at minimum show monitoring; under pressure it should show "Killed <cgroup>" entries that point at the build cgroup, not system services).
- [ ] `dmesg | grep -i "out of memory" | tail` shows no kernel-OOM-killer activity (entries with "invoked oom-killer" mean kernel OOM fired — a failure mode we're trying to avoid).
- [ ] `cat /sys/kernel/debug/zswap/stored_pages` is non-zero — confirms zswap actually held pages during the load.

If any criterion fails, **DO NOT proceed to Task 9.** Investigate and either tune the ceilings or roll back the offending change. Mode 2 + ratio=250 is still acting as backstop.

- [ ] **Step 5: No commit (this is a verification task).**

If validation is clean, proceed to Task 9.

---

### Task 9: Final cutover — heuristic overcommit

**Files:**
- Modify: `hosts/nixos/ada/hardware.nix` (sysctl block)

Drops `vm.overcommit_memory=2` and removes `overcommit_ratio` entirely. Cgroup containment becomes the sole memory protection.

- [ ] **Step 1: Update the sysctl block**

In `hosts/nixos/ada/hardware.nix`, find the validation-mode sysctl block (set in Task 6):

```nix
  boot.kernel.sysctl = {
    # Validation phase: strict overcommit retained as a backstop while we
    # verify cgroup containment under load. Wide budget (64G swap + 250% × 64G
    # RAM ≈ 224G) lets legitimate sci-python and docker builds proceed.
    # Task 9 of the plan switches this to mode 0 once cgroup containment is
    # validated.
    "vm.overcommit_memory" = 2;
    "vm.overcommit_ratio" = 250;

    # Less aggressive than the previous 133 ...
    "vm.swappiness" = 100;
    ...
  };
```

Replace with:

```nix
  boot.kernel.sysctl = {
    # Heuristic overcommit. Layer 2 (per-cgroup MemoryMax) is the actual
    # protection against runaways; mode 2 was redundant after cgroup
    # containment landed and was blocking legitimate sci-python and docker
    # builds. See docs/superpowers/specs/2026-04-29-ada-memory-tuning-design.md
    # for the four-layer architecture.
    "vm.overcommit_memory" = 0;

    # zswap+Optane is fast enough that aggressive anon-prefer (was 133 with
    # zram) is unnecessary; 100 keeps anon and file-cache reclaim balanced.
    "vm.swappiness" = 100;

    # Wake kswapd at ~2% free RAM (~1.3GB on 64GB) instead of the default
    # 0.1% (~64MB). Default is too late on big-memory boxes.
    "vm.watermark_scale_factor" = 200;

    # Bias toward keeping file cache under pressure. Helps nix-store reads
    # + ZFS ARC interactions.
    "vm.vfs_cache_pressure" = 50;
  };
```

The `vm.overcommit_ratio` entry is removed entirely (only mode 2 reads it).

- [ ] **Step 2: Verify host evaluation**

```bash
nix eval --raw .#nixosConfigurations.ada.config.system.build.toplevel.drvPath > /dev/null
```

Expected: exit 0.

- [ ] **Step 3: Confirm sysctl changes**

```bash
nix eval --json .#nixosConfigurations.ada.config.boot.kernel.sysctl
```

Expected JSON: an object with `"vm.overcommit_memory": 0`, `"vm.swappiness": 100`, `"vm.watermark_scale_factor": 200`, `"vm.vfs_cache_pressure": 50`. **`vm.overcommit_ratio` must NOT be present.**

- [ ] **Step 4: Build and activate**

```bash
nix build .#nixosConfigurations.ada.config.system.build.toplevel --no-link
sudo nixos-rebuild switch --flake .#ada
```

Expected: build + activate succeed.

- [ ] **Step 5: Verify runtime sysctl**

```bash
sysctl vm.overcommit_memory vm.overcommit_ratio vm.swappiness vm.watermark_scale_factor vm.vfs_cache_pressure
```

Expected:
- `vm.overcommit_memory = 0`
- `vm.overcommit_ratio = 50` (this is the kernel default that gets restored when no override is set; harmless because mode 0 ignores it)
- `vm.swappiness = 100`
- `vm.watermark_scale_factor = 200`
- `vm.vfs_cache_pressure = 50`

- [ ] **Step 6: Watch for 30 minutes under normal load**

Run normal interactive work for ~30 minutes. Open browser, do typical tasks, run a small build. In another terminal:

```bash
journalctl -f -u systemd-oomd -u dbus -u systemd-journald -u sshd
```

Expected: no kills of critical services, no unexpected oomd activity. Routine memory pressure events from oomd are fine; killing user.slice or docker.slice cgroups during a build is fine; killing dbus/journald/sshd is NOT fine.

- [ ] **Step 7: Commit**

```bash
git add hosts/nixos/ada/hardware.nix
git commit -m "ada: cut over to heuristic overcommit

Strict overcommit (mode 2) is removed. Cgroup containment via
chrisportela.memory-protection is now the sole protection layer.
overcommit_ratio is removed (only mode 2 reads it).
"
```

---

### Task 10: Update memory note to reflect new architecture

**Files:**
- Modify: `~/.claude/projects/-home-cmp-src-dotfiles/memory/feedback_overcommit_strict.md`
- Possibly modify: `~/.claude/projects/-home-cmp-src-dotfiles/memory/MEMORY.md` (if the title or description changes meaningfully)

The original memory said "ada's strict overcommit is intentional; toggle the sysctl per-build, don't propose relaxing it permanently." That guidance is now superseded.

- [ ] **Step 1: Read the current memory file**

```bash
cat ~/.claude/projects/-home-cmp-src-dotfiles/memory/feedback_overcommit_strict.md
```

- [ ] **Step 2: Replace its contents with the updated guidance**

The memory file should be rewritten to reflect that the previous workaround has been superseded by a proper architecture. Suggested content (preserving the frontmatter format):

```markdown
---
name: ada memory protection architecture
description: ada uses cgroup-based memory protection (chrisportela.memory-protection module), not strict overcommit. Diagnose memory issues via systemd-cgls / oomctl / oomd logs.
type: feedback
---

ada's memory protection is layered (see docs/superpowers/specs/2026-04-29-ada-memory-tuning-design.md):
- Layer 1: zswap + Optane swap
- Layer 2: cgroup MemoryMax/MemoryHigh on nix-daemon, docker.slice, user.slice (chrisportela.memory-protection module)
- Layer 3: systemd-oomd with 10s pressure duration + 90% swap-used limit
- Layer 4: OOMScoreAdjust + ManagedOOMPreference=avoid + MemoryMin on dbus, journald, sshd, logind, NetworkManager, tailscaled

**Why:** Previous architecture used `vm.overcommit_memory=2` to refuse runaway commits. That blocked legitimate sci-python and docker builds (which reserve large virtual address spaces without ever touching them). Replacing it with cgroup-based protection means builds get unrestricted virtual address space; runaways are contained in their own cgroup; critical services keep working.

**How to apply:** Don't propose `vm.overcommit_memory=2` as a fix for memory issues on ada. If a service is being killed unexpectedly, look at:
- `systemd-cgls` — which cgroup is the runaway in?
- `oomctl` — what is oomd watching, and at what pressure?
- `journalctl -u systemd-oomd` — recent kills and reasons
- `dmesg | grep -i "out of memory"` — kernel OOM activity (should be rare; if firing, it indicates cgroup containment escaped)

If a new service or workload type starts running on ada that needs cgroup containment, add it to the chrisportela.memory-protection module options rather than inline-tweaking the host file.
```

Write this with the Write tool to the file at `/home/cmp/.claude/projects/-home-cmp-src-dotfiles/memory/feedback_overcommit_strict.md`.

- [ ] **Step 3: Update MEMORY.md if needed**

```bash
cat ~/.claude/projects/-home-cmp-src-dotfiles/memory/MEMORY.md
```

If the existing entry is `- [feedback_overcommit_strict.md](feedback_overcommit_strict.md) — ada's strict overcommit is intentional; toggle the sysctl per-build, don't propose relaxing it permanently`, replace its one-liner with something like:

```
- [feedback_overcommit_strict.md](feedback_overcommit_strict.md) — ada uses cgroup-based memory protection (chrisportela.memory-protection module), not strict overcommit
```

Use the Edit tool for this targeted replacement.

- [ ] **Step 4: No git commit**

The memory directory is outside the dotfiles repo (it's in `~/.claude/projects/...`), so there's no commit. The Claude memory system persists the file directly.

---

## Final state

After Task 10, the worktree contains:

- New module `modules/nixos/memory-protection/` (default.nix + README.md)
- Module registered in `modules/nixos/default.nix` and `modules/nixos/all.nix`
- `hosts/nixos/ada/hardware.nix` updated: heuristic overcommit, new sysctls, zswap (zram disabled), module enablement, systemd-oomd tuning
- Spec at `docs/superpowers/specs/2026-04-29-ada-memory-tuning-design.md` (already committed)
- Plan at `docs/superpowers/plans/2026-04-29-ada-memory-tuning.md` (this file)
- Memory note rewritten to reflect new architecture

Out of band (recorded as follow-ups in the spec):
- Optional Optane swap growth to 128GB (separate plan; requires ZFS log/special vdev resilver)
- Optional flamme migration to the same module (cleanup, not new behavior)
- Optional kernel 6.8+ `MemoryZSwapWriteback` per-cgroup tuning
