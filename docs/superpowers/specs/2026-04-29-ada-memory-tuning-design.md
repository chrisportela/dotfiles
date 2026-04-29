# ada Memory Tuning Design

## Goal

Replace `vm.overcommit_memory=2` (strict accounting) with cgroup-based memory protection so scientific Python builds, docker builds, and other large-virtual-commit workloads stop failing with spurious `ENOMEM`, while keeping critical system services (dbus, journald, sshd, etc.) protected from runaway allocations.

Switch from `zram` (32GB compressed RAM swap) to `zswap` (compressed pool over Optane backing) to take fuller advantage of the host's 4×16GB Intel Optane SSD swap and free 64GB RAM for application working set.

## Problem

The current ada configuration uses `vm.overcommit_memory=2` with `overcommit_ratio=95`, giving a system-wide commit budget of ~157GB (64GB swap + 32GB zram + 95% × 64GB RAM). Modern build systems — pytorch, scipy, jax, numpy with LAPACK, glibc-threaded programs, JVM workloads, and many Docker base images — reserve very large virtual memory regions (per-thread arenas, sparse allocations, mmap-with-MAP_NORESERVE-cleared) that count against this budget without ever becoming RSS. Builds fail with `ENOMEM` despite ample physical RAM and swap.

Previous attempts to relax overcommit (`vm.overcommit_memory=0` or `=1` globally) caused critical system services to be killed by the kernel OOM killer when builds went runaway, because cgroup ceilings only existed on `nix-daemon.service`. Other large memory consumers (`docker.service`, user-shell builds, `nix develop` work) had no containment.

## Architecture

Four-layer memory protection:

```
┌─ Layer 4: kernel OOM killer (last-resort)
│   OOMScoreAdjust biases away from systemd, dbus, sshd, etc.
├─ Layer 3: systemd-oomd (PSI-based pre-OOM)
│   Watches per-cgroup memory + swap pressure, kills offending cgroup.
├─ Layer 2: cgroup MemoryMax / MemoryHigh (the real safety net)
│   Per-service hard ceilings on nix-daemon, docker.service, user.slice.
│   A runaway in any cgroup is contained inside that cgroup.
└─ Layer 1: zswap + Optane swap (pressure relief)
    Hot pages compressed in RAM; cold pages spill to Optane.
```

### Key shifts from current state

| Today | After |
|---|---|
| `vm.overcommit_memory=2`, `overcommit_ratio=95` | `vm.overcommit_memory=0` (heuristic) |
| 32GB zram (50% RAM, zstd) | zswap (40% pool, zstd, zsmalloc) |
| `vm.swappiness=133` | `vm.swappiness=100` |
| `nix-daemon` is the only cgroup with ceilings (55G/48G) | `nix-daemon` (90G/75G), `docker.slice` (90G/75G), `user.slice` (100G/85G) |
| Critical-service hardening: `dbus`, `journald` only | Adds `sshd`, `systemd-logind`, `NetworkManager`, `tailscaled`, with `OOMScoreAdjust` and `MemoryMin` reservations |
| Inline cgroup config in host file | Reusable `chrisportela.memory-protection` module |

## Module: `modules/nixos/memory-protection/`

### Purpose

Provide cgroup-based memory containment (Layer 2) and critical-service hardening (Layer 4) as reusable NixOS module options. Hosts opt in and supply ceilings appropriate for their hardware.

Sysctls (Layer 1) and `systemd-oomd` defaults (Layer 3) stay in the host file because they encode storage-hardware assumptions (Optane swap, ZFS/ARC interaction, RAM size) that don't transfer to other hosts.

### Options

```nix
chrisportela.memory-protection = {
  enable = lib.mkEnableOption "cgroup-based memory protection";

  nixDaemon = {
    enable = lib.mkEnableOption "nix-daemon cgroup ceilings";
    memoryMax = lib.mkOption { type = lib.types.str; example = "90G"; };
    memoryHigh = lib.mkOption { type = lib.types.str; example = "75G"; };
  };

  dockerSlice = {
    enable = lib.mkEnableOption "docker.slice with cgroup ceilings";
    memoryMax = lib.mkOption { type = lib.types.str; example = "90G"; };
    memoryHigh = lib.mkOption { type = lib.types.str; example = "75G"; };
  };

  userSlice = {
    enable = lib.mkEnableOption "user.slice cgroup ceilings";
    memoryMax = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "100G";
    };
    memoryHigh = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "85G";
    };
  };

  microvmHost = lib.mkEnableOption "host-side OOM settings for microvm@.service";
};
```

### Always-on behaviour (when `enable = true`)

Critical-service hardening — applied unconditionally regardless of which opt-in sub-options are set:

| Service | OOMScoreAdjust | ManagedOOMPreference | MemoryMin |
|---|---|---|---|
| `dbus` | -900 | avoid | 64M |
| `systemd-journald` | -900 | avoid | 128M |
| `sshd` | -900 | avoid | 32M |
| `systemd-logind` | -900 | avoid | — |
| `NetworkManager` | -800 | avoid | — |
| `tailscaled` | -800 | avoid | — |

`NetworkManager` and `tailscaled` settings are guarded by `lib.mkIf config.networking.networkmanager.enable` and `lib.mkIf config.services.tailscale.enable` respectively, so the module doesn't force those services on.

### Opt-in behaviour

**`nixDaemon.enable`:**

```nix
systemd.services.nix-daemon.serviceConfig = {
  ManagedOOMMemoryPressure = "kill";
  ManagedOOMMemoryPressureLimit = "80%";
  MemoryMax = cfg.nixDaemon.memoryMax;
  MemoryHigh = cfg.nixDaemon.memoryHigh;
};
```

**`dockerSlice.enable`:** moves `docker.service` into a `docker.slice` cgroup, sets ceilings on the slice (which contains both the daemon and all containers), and configures dockerd to inherit the slice for child containers.

```nix
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
```

**`userSlice.enable`** (only applies if both `memoryMax` and `memoryHigh` are non-null):

```nix
systemd.slices."user".sliceConfig = {
  MemoryMax = cfg.userSlice.memoryMax;
  MemoryHigh = cfg.userSlice.memoryHigh;
  ManagedOOMMemoryPressure = "kill";
  ManagedOOMMemoryPressureLimit = "80%";
};
```

**`microvmHost`:**

```nix
systemd.services."microvm@".serviceConfig = {
  OOMScoreAdjust = 200;
  ManagedOOMPreference = "omit";
};
```

`OOMScoreAdjust=200` (positive) biases the kernel toward killing a VM before host services if a memory crisis ever escapes cgroup containment. `ManagedOOMPreference=omit` tells systemd-oomd to ignore the VM cgroup when picking victims — VMs are statically sized via microvm.nix's `mem` setting, so killing one means losing the *whole* VM rather than the actual runaway inside it; oomd should target user.slice / docker.slice / nix-daemon instead.

### Module registration

Added to `modules/nixos/default.nix` (the aggregator) so it is available wherever NixOS configurations are built. Migration of `flamme` to use the same module is out of scope here but the module is shaped to support it.

### README

`modules/nixos/memory-protection/README.md` documents:
- Purpose (the four-layer architecture)
- All options and their semantics
- Dependencies (`systemd.oomd` should be enabled by the host; the module does not enable it)
- Gotchas:
  - Setting `dockerSlice.enable = true` requires `virtualisation.docker.enable = true`; otherwise the `docker.slice` is created but unused.
  - `user.slice` ceilings affect *all* user-session processes including KDE Plasma, browsers, and games — set generously.
  - `MemoryMin` reservations require cgroup v2 (NixOS default since 23.05).

## Host config: `hosts/nixos/ada/hardware.nix`

### Sysctls (Layer 1)

Replace lines 73–85 with:

```nix
boot.kernel.sysctl = {
  "vm.overcommit_memory" = 0;       # heuristic — was 2 (strict)
  "vm.swappiness" = 100;            # was 133
  "vm.watermark_scale_factor" = 200; # new — wake kswapd at ~1.3GB free instead of 64MB
  "vm.vfs_cache_pressure" = 50;     # new — bias against file-cache eviction
};
```

`vm.overcommit_ratio` is removed (only mode 2 reads it).

### zswap (Layer 1)

```nix
boot.kernelParams = [
  "zswap.enabled=1"
  "zswap.compressor=zstd"
  "zswap.zpool=zsmalloc"
  "zswap.max_pool_percent=40"
  "zswap.shrinker_enabled=Y"
];

zramSwap.enable = false;  # was: enable=true, memoryPercent=50
```

### Swap priorities (Layer 1)

The existing 4×16GB Optane swap partitions are configured by `disko.nix` and need explicit equal `priority` values to ensure the kernel stripes across them rather than filling sequentially.

Implementation note: verify whether disko's `swap` content type already wires partitions through `swapDevices` with default priority, or whether explicit `swapDevices` entries need to be added. If disko already handles it with a non-explicit (or all-zero) priority, the kernel will already stripe; in that case no change. If priorities differ between drives, add an explicit `swapDevices` block in `hardware.nix` setting `priority = 100` on all four. Decide during implementation by reading current `/proc/swaps` output.

### Module enablement (Layer 2 + 4)

Replace the inline `dbus`/`journald` `ManagedOOMPreference` block (lines 105–106) and the `nix-daemon.serviceConfig` block (lines 111–116) with:

```nix
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

### systemd-oomd (Layer 3)

The existing `systemd.oomd` block (lines 97–102) is replaced — `enable`/`enable*Slice` flags carry over, only `extraConfig` is added:

```nix
systemd.oomd = {
  enable = true;
  enableRootSlice = true;
  enableUserSlices = true;
  enableSystemSlice = true;
  extraConfig = {
    DefaultMemoryPressureDurationSec = "10s";  # was implicit 30s
    SwapUsedLimit = "90%";                     # explicit
  };
};
```

## Sizing rationale

Host has 64GB RAM + 64GB Optane swap = 128GB total physical+swap.

| Cgroup | MemoryMax | MemoryHigh | Reasoning |
|---|---|---|---|
| `nix-daemon` | 90G | 75G | Fits a typical sci-python or CUDA build (~30–60G RSS) plus working set + ~20G headroom into Optane swap. Was 55G/48G when zram held 32GB. |
| `docker.slice` | 90G | 75G | Same reasoning as nix-daemon — heavy docker builds (e.g., ML images) reach similar working-set sizes. |
| `user.slice` | 100G | 85G | Higher than build slices because user shell may run KDE Plasma + browser + Steam + ad-hoc `nix develop` build concurrently. Cap exists to bound a runaway, not to constrain normal use. |

Ceilings sum to 280G — far exceeds 128G physical+swap. This is intentional: each ceiling is the *worst-case single-cgroup* budget; concurrent usage is arbitrated by `systemd-oomd` based on memory pressure, not by ceiling arithmetic. In practice, only one of nix-daemon / docker.slice / user.slice runs heavy at a time.

## Migration plan

Order matters; the box must remain protected during transition. The trick: validating cgroup containment requires running the previously-failing builds, but those builds will still fail under mode 2 with `overcommit_ratio=95`. So during validation we keep strict mode active but raise the budget high enough that real builds proceed and we can witness cgroup behavior under load.

1. **Land module without enabling on ada.** Module added to `modules/nixos/memory-protection/`, registered in `modules/nixos/default.nix`. Ada's host file unchanged. Confirms Nix syntax and type-checks options. Build + activate succeeds with no behaviour change.

2. **Enable on ada in validation mode.** Ada's `hardware.nix` switches to the module (cgroup containment), enables zswap, disables zram, applies the new sysctls (`swappiness=100`, `watermark_scale_factor=200`, `vfs_cache_pressure=50`), but *keeps* `vm.overcommit_memory=2` with `overcommit_ratio=250` (rather than removing the ratio entirely). Commit budget becomes 64GB swap + 250%×64GB RAM ≈ 224GB — large enough that legitimate sci-python and docker builds succeed, while strict mode remains as a backstop in case cgroup containment misbehaves.

3. **Verify under load.** Run a previously-failing workload (a docker build or `nix build` of a CUDA-using sci-python derivation). Confirm:
   - Build completes — cgroup ceiling did not block real usage.
   - System remains responsive throughout.
   - Critical services (`dbus`, `sshd`, `systemd-journald`) show no kills in `journalctl -u <svc>`.
   - `systemd-cgls` shows the build inside its expected slice (`docker.slice` or `system.slice/nix-daemon.service`).
   - `oomctl` reports the slices are being monitored.
   - `cat /sys/kernel/debug/zswap/stored_pages` is non-zero under load (zswap actively compressing).

   If any of these fail, mode 2 with the wide budget is still active — drop the slice ceilings or roll back the module entirely. Previous behavior is preserved.

4. **Flip to heuristic overcommit.** Change `vm.overcommit_memory=0` and remove the `vm.overcommit_ratio` line entirely (only mode 2 reads it). Final rebuild. Cgroup containment is now the sole protection layer.

5. **Update memory note.** Edit `~/.claude/projects/-home-cmp-src-dotfiles/memory/feedback_overcommit_strict.md` to reflect the new architecture: strict overcommit superseded by cgroup containment via `chrisportela.memory-protection`. Future memory diagnosis should use `systemd-cgls`, `oomctl`, and `journalctl -u systemd-oomd` rather than reaching for the overcommit sysctl.

### Rollback path

Each step is a single git revert away. Through step 3, mode 2 is still active (just with a generous ratio), so rollback to step 1 restores the original protection. After step 4, rollback restores mode 2 alongside the cgroup config — both layers active, which is harmless.

## Out of scope (follow-ups)

### Grow Optane swap

The user's workload mix (concurrent heavy builds, VMs, and interactive desktop) wants more than the current 64GB swap. The motivation is to raise per-cgroup ceilings (`nixDaemon`, `dockerSlice`, `userSlice`) higher and have physical+swap headroom to back them. Target: ~128GB swap (4×32GB).

The four Intel Optane P1600X drives are dual-use, with **two very different ZFS roles** that have very different growability:

- **`intel-ssd0/1` — SLOG mirror (ZFS Intent Log):** *removable* without data loss. SLOG holds in-flight ZIL records; `zpool remove tank mirror-1` flushes them to the main pool, then releases the devices. SLOG is also wildly oversized currently — typical usage is < 1GB; the 102GB allocation is overkill. **Safely growable to ~32GB swap each** (gain: +32GB total swap).
- **`intel-ssd2/3` — special vdev mirror (metadata + small blocks):** *not removable* from a `raidz1` pool. Once added, special vdev is permanent. ZFS also doesn't support shrinking a vdev — `zpool replace` requires the new device to be ≥ the old one's *size*, not its *used*. Detach-resize-reattach will fail because the resized LUKS container is smaller than the existing vdev. **Cannot be grown without recreating the pool.**

**Recommended progression:**

1. **Observe first.** Run with current 64GB swap for several weeks. Monitor `journalctl -u systemd-oomd --grep=killed` and `/proc/pressure/{memory,io}` for genuine pressure events. If none surface, current swap is sized right.
2. **Raise cgroup ceilings before growing swap.** If a specific workload (e.g., a heavy CUDA build) hits its ceiling, raise the relevant `chrisportela.memory-protection.{nixDaemon,dockerSlice,userSlice}.memoryMax` first. That's a one-line config change, no hardware risk. Cgroup ceiling and swap size are independent levers — bigger ceilings only need bigger swap when the *summed* concurrent demand exceeds physical+swap.
3. **Phase 1 — SLOG repartition (modest gain, low risk):** Free up `intel-ssd0/1` as described above. Net: 64GB → 96GB swap. Procedure outlined below.
4. **Phase 2 — Pool migration (full gain, real downtime):** Backup `tank/main` to a separate target, destroy and recreate the pool with the desired Optane layout (32GB swap + ~70GB special each), restore data. Net: 96GB → 128GB swap. Requires backup capacity for the full pool and a downtime window. Out of scope for any incremental work — deserves its own plan with explicit backup/recovery steps.

**Phase 1 procedure outline (SLOG drives, no data loss):**

```bash
# Flush ZIL to main pool, remove the SLOG mirror
sync
sudo zpool remove tank mirror-1
sudo zpool status tank   # wait for "logs" section to disappear

# Close LUKS, swapoff
sudo cryptsetup close crypt-intel-ssd0
sudo cryptsetup close crypt-intel-ssd1
sudo swapoff /dev/disk/by-partlabel/disk-intel-ssd0-swap
sudo swapoff /dev/disk/by-partlabel/disk-intel-ssd1-swap

# Repartition (sgdisk or update disko + run imperatively on those devices)
# New layout per drive: 32GB swap + ~80GB LUKS (with 4-8GB SLOG to spare)

# Recreate LUKS
sudo cryptsetup luksFormat ... /dev/disk/by-partlabel/disk-intel-ssd0-luks
sudo cryptsetup luksFormat ... /dev/disk/by-partlabel/disk-intel-ssd1-luks
sudo cryptsetup open ... crypt-intel-ssd0
sudo cryptsetup open ... crypt-intel-ssd1

# Re-add as new SLOG mirror (size determined by smaller LUKS now)
sudo zpool add tank log mirror /dev/mapper/crypt-intel-ssd0 /dev/mapper/crypt-intel-ssd1

# Reactivate swap (NixOS recreates random-encrypted swap automatically on next boot
# with randomEncryption=true; or run `nixos-rebuild switch` to apply the new disko spec)
```

Update `disko.nix` to reflect the new layout so subsequent installs / disaster recovery rebuild correctly. Disko is declarative for *initial* provisioning; live repartitioning is imperative, but the spec should match the final state.

### Other follow-ups

- **Migrate `flamme` to `chrisportela.memory-protection`.** flamme's existing inline cgroup config (`hosts/nixos/flamme/hardware.nix:90–100`) replicates the same pattern at smaller scale. Replacing it with the module is cleanup, not new behavior.
- **Per-cgroup `MemoryZSwapWriteback` toggles.** Kernel 6.8+ feature allowing a cgroup to opt out of writing zswap-compressed pages to disk swap. Useful for KDE Plasma (prefer responsiveness loss over Optane writes). Revisit once the basic system is stable.

## Testing

Manual verification in step 3 of migration. No automated tests — memory-pressure behavior is hard to make deterministic in unit tests, and the existing repo does not have an integration-test harness for NixOS configs.

Post-rollout sanity checks:

```bash
# All three slices present and limited
systemctl status user.slice docker.slice
systemctl show nix-daemon.service -p MemoryMax,MemoryHigh

# zswap active, zram absent
cat /sys/kernel/debug/zswap/pool_total_size
cat /proc/swaps  # should show 4 Optane partitions, no /dev/zram0
swapon --show

# Critical services have OOMScoreAdjust
for svc in dbus systemd-journald sshd systemd-logind; do
  systemctl show "$svc" -p OOMScoreAdjust,ManagedOOMPreference,MemoryMin
done

# oomd watching everything
oomctl
```
