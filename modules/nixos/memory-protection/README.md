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
- `userSlice.memoryMax` / `memoryHigh` — Nullable; **both must be set** (non-null) for the cap to apply. If `enable=true` but either value is null, the user.slice cap silently no-ops.
- `microvmHost` — Apply host-side OOM settings to `microvm@.service` (a systemd template unit; settings apply to every `microvm@<name>` instance) so the kernel prefers killing whole VMs over host services in a memory crisis.

## Dependencies

- `systemd` cgroup v2 (NixOS default since 23.05) — required for `MemoryMin` reservations to be effective.
- `systemd-oomd` should be enabled by the host (`systemd.oomd.enable = true`). The module does not enable it; `ManagedOOM*` directives only do anything if oomd is running.
- `dockerSlice.enable = true` requires `virtualisation.docker.enable = true`. Otherwise `docker.slice` is created but unused (no error, just no effect).
- `microvmHost = true` requires `microvm.nix` integration (the host imports `inputs.microvm.nixosModules.host`).

## Gotchas

- **`user.slice` caps affect the entire interactive session** — including KDE Plasma, browsers, games, and `nix develop` shells. Set generously; a runaway in *any* user process counts against the cap.
- **`docker.slice` requires the systemd cgroup driver.** The module configures `daemon.json` accordingly. If a host had docker configured with `cgroup-driver=cgroupfs`, switching may require a docker daemon restart and may invalidate cached image metadata.
- **Critical-service hardening uses `OOMScoreAdjust=-900`, not `-1000`.** -1000 disables the OOM killer for the PID entirely, which is risky if the service itself runs away. -900 strongly biases against killing while still allowing it as a last resort.
- **`MemoryMin` is a reservation, not a request.** Pages held by services with `MemoryMin` are reclaimed last under pressure, leaving their working sets alone. Effective only with cgroup v2.
- **`microvm@` is a template unit.** The module sets `serviceConfig` on the template, so every instantiated `microvm@<vm-name>.service` inherits the host-side OOM bias (`OOMScoreAdjust=200`, `ManagedOOMPreference="omit"`).

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
