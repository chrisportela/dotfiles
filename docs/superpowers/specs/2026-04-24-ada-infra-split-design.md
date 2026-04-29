# Make ada an "infra" host — design

## Goal

Reshape ada so its public-facing baseline lives in dotfiles (buildable, useful
for recovery) while its private services live in `~/src/infra` alongside ciri
and liara. lux, roxy, flamme, rpi4, and the installer stay fully in dotfiles.

The split is designed so a future "complete move to infra" is incremental, not
a rewrite.

## Non-goals

- Not changing flamme, lux, roxy, rpi4, or the installer host.
- Not redesigning any moved module — they ship to infra "as-is." The pending
  per-user samba secrets work continues, but on the infra side now.
- Not changing the home-manager config for `cmp@ada`
  (`legacyPackages.homeConfigurations."cmp@ada"` stays in dotfiles, sibling to
  `cmp@flamme` and `cmp@roxy`).
- Not touching the infra repo from this worktree. Infra-side work is described
  here for the user's reference and is a separate task.

## Architecture

Two flakes, each with a `nixosConfigurations.ada`:

- **dotfiles' ada** = baseline. Buildable. Trusts the cafecito.cloud root CA,
  has KDE/virtualization/ZFS/NVIDIA, but no private services. Used for
  recovery, CI, and as a flake input by infra.
- **infra's ada** = production. Imports dotfiles' baseline and layers private
  modules and host config on top. This is what gets deployed to the real
  machine.

```
~/src/dotfiles                          ~/src/infra
├── flake.nix                           ├── flake.nix
│   nixosConfigurations.ada =           │   inputs.dotfiles.url = ...
│     mkHost { config = ./hosts/        │   nixosConfigurations.ada = mkHost {
│              nixos/ada; ... };        │     config = ./hosts/ada;
│   (BASELINE — buildable, not          │     extraModules = [
│    deployed to real machine)          │       dotfiles.nixosConfigurations
│                                       │         .ada (or modules + host)
└── modules/nixos/                      │       ./modules/nixos/samba
    ├── (kept) common, network,         │       ./modules/nixos/ftp
    │   openssh, gaming, nginx-         │       ./modules/nixos/local-llm
    │   cloudflare, hardware/, disko/,  │       ./modules/nixos/cafecitocloud-acme
    │   nixpkgs, agent-vms,             │     ];
    │   cafecitocloud (trust only)      │   };
    └── (gone) ftp, local-llm, samba    │
                                        └── secrets/ada-samba-passwords.age
                                            (re-encrypted with infra keyring)
```

## Module split

Modules and their host-config usage **move together** when private-flavored
**and the module has only one consumer (ada)**. Modules with consumers besides
ada (e.g. `agent-vms`, also used by flamme) stay in dotfiles; only ada's
invocation moves. The cafecitocloud module splits in two so all hosts keep CA
trust without leaking infra details.

| Module                | Where         | Notes                                       |
|-----------------------|---------------|---------------------------------------------|
| `common`              | dotfiles      | unchanged                                   |
| `network`             | dotfiles      | unchanged                                   |
| `openssh`             | dotfiles      | unchanged                                   |
| `nixpkgs`             | dotfiles      | unchanged                                   |
| `gaming`              | dotfiles      | unchanged                                   |
| `nginx-cloudflare`    | dotfiles      | unchanged                                   |
| `hardware/`           | dotfiles      | unchanged (rpi4 profile)                    |
| `disko/`              | dotfiles      | unchanged                                   |
| `agent-vms/`          | dotfiles      | **stays** — flamme uses it; ada's invocation moves to infra |
| `cafecitocloud`       | dotfiles      | **trimmed** to CA trust only                |
| `cafecitocloud-acme`  | infra         | **new**, carved out of `cafecitocloud`      |
| `ftp.nix`             | infra         | move file (infra can promote to a dir)      |
| `local-llm/`          | infra         | move whole directory                        |
| `samba/`              | infra         | move whole directory                        |

Infra-side modules go in `modules/nixos/<name>/` (per-module directory with
`default.nix` and `README.md`) following dotfiles' convention from CLAUDE.md.
Improving infra to match this layout fully is out of scope for this work.

## Dotfiles changes (this worktree's scope)

### `modules/nixos/` — removed
- `ftp.nix`
- `local-llm/` (whole directory)
- `samba/` (whole directory)

`agent-vms/` stays in dotfiles — flamme also uses it. Only the ada-side
invocation of `chrisportela.agent-vms` moves to infra. Infra consumes the
agent-vms module via the dotfiles flake input.

### `modules/nixos/cafecitocloud/default.nix` — trimmed
Drop the `enableACME` option and the `security.acme.defaults` block. Keep
`security.pki.certificateFiles = [ ./cafecitocloud-root_ca.crt ]` and the
`.crt` file. The module becomes "trust the cafecito.cloud root CA," nothing
more. All hosts (lux, roxy, flamme, ada baseline) can flip
`cafecitocloud.enable = true`.

### `modules/nixos/default.nix` — updated
Remove the `ftp` and `local-llm` keys from the returned attrset (`agent-vms`
and `samba` are not in this attrset today). The `agent-vms` key stays.

### `modules/nixos/all.nix` — updated
Remove `./ftp.nix`, `./local-llm`, and `./samba` from the `imports` list.
`./agent-vms` stays.

### `hosts/nixos/ada/default.nix` — stripped

Remove:
- The `chrisportela.{samba, ftp, agent-vms, local-llm}` blocks
- `cafecitocloud.enableACME = true` (just `cafecitocloud.enable = true` remains)
- `services.elasticsearch` block
- `virtualisation.oci-containers.containers.kibana-test`
- `services.nginx` block (the `kibana.ada.i.cafecito.cloud` vhost) and the
  `users.users.nginx.extraGroups` line
- `users.users.coder-provisioner` and `users.groups.coder-provisioner`
- `age.secrets.ada-samba-passwords` line
- `elasticsearch` from `allowedUnfree`

Keep (baseline):
- `allowedUnfree` covers `claude-code`, `nvidia-persistenced`,
  `nvidia-settings`, `nvidia-x11`, `ookla-speedtest`, plus a CUDA slice
  (`cuda-merged`, the `cuda_*` family, the `lib*`/`cudnn` family) needed by
  `nvtopPackages.full` once `local-llm` is no longer providing the
  whitelist. `cudaSupport = true` (which the old `local-llm` module set) is
  intentionally NOT carried over — that flag belongs to infra's LLM modules,
  not the recovery baseline.
- `cafecitocloud.enable = true` (CA trust)
- `chrisportela.network = { speedtest-utils, mDNS };`
- `chrisportela.gaming.enable = true`
- Hardware and networking identity: `hostId`, bridges, interfaces, firewall
- `systemd.services.tailscaled.after`, `systemd.network.wait-online`
- KDE Plasma 6 + SDDM (`services.desktopManager.plasma6`,
  `services.displayManager.sddm`, `services.xserver.dpi`,
  `security.pam.services.kwallet.enableKwallet`)
- `programs.firefox.enable`, `programs.localsend`
- Virtualization stack: `virtualisation.{virtualbox, libvirtd, docker,
  oci-containers.backend}`, `services.spice-vdagentd`,
  `programs.virt-manager`, `programs.dconf`,
  `boot.extraModprobeConfig` for nested KVM
- `services.zfs.{trim, autoScrub}`
- `hardware.nvidia-container-toolkit.enable`
- `boot.binfmt` cross-compilation block (aarch64/armv6l + fast qemu wrapper)
- `nix.settings.trusted-users`
- `users.users.cmp.extraGroups` (without `coder-provisioner`-related groups)
- `services.vscode-server.enable`
- The `environment.systemPackages` desktop list (`nvtopPackages.full`,
  `psmisc`, `rclone`, `git-annex-remote-rclone`, `reptyr`, `rmlint`, `wget`,
  `curl`, `kdePackages.{plasma-thunderbolt, kate}`, `rclone-browser`,
  `cachix`, `virt-manager`, `virt-viewer`, `spice`, `spice-gtk`,
  `spice-protocol`, `virtio-win`, `win-spice`, `disko`)

### `secrets/` — updated
- `ada-samba-passwords.age` deleted from dotfiles
- Entry for `ada-samba-passwords.age` removed from `secrets/secrets.nix`
- The `adaHost` and `ada` local bindings in `secrets.nix` can be cleaned up if
  they have no other users (likely yes, since `ada-samba-passwords` was their
  only consumer)

### Unchanged in dotfiles
- `flake.nix` `nixosConfigurations.ada` entry — same `mkHost` call, same
  `hardwareConfig` and `config` paths, same rmlint overlay.
- `flake.nix` `legacyPackages.homeConfigurations."cmp@ada"` — stays.
- `lib/ssh-keys.nix` — `nixDesktop` (the `cmp@ada` user key) and the `hosts.ada`
  entry stay; they identify the user/host across the fleet.
- `hosts/nixos/ada/hardware.nix` and `hosts/nixos/ada/disko.nix` — unchanged.

## What infra absorbs (out of scope, for reference)

The work on the infra side, which the user does separately. **All infra-side
changes must happen in a worktree created with `wt add <branchname>` — not
on `main` or in the root of `~/src/infra`.**

- Copy `modules/nixos/{samba, local-llm}` and `modules/nixos/ftp.nix` from
  dotfiles into infra's `modules/nixos/`. `agent-vms` stays in dotfiles
  (flamme uses it); infra consumes it via the dotfiles flake input.
- Create `modules/nixos/cafecitocloud-acme/` in infra holding the
  `security.acme.defaults` block (server, dnsResolver, email, validMinDays,
  renewInterval) plus an `enable` option.
- Create `hosts/ada/default.nix` in infra containing the host-config blocks
  removed from dotfiles (the `chrisportela.*` invocations, elasticsearch,
  kibana container, kibana nginx vhost, `coder-provisioner` user,
  `age.secrets.ada-samba-passwords`).
- Move `secrets/ada-samba-passwords.age` to infra's secrets directory and
  re-encrypt it with infra's keyring; add the corresponding entry to infra's
  `secrets.nix` with the right host/user keys.
- Add a `nixosConfigurations.ada` to infra's flake that imports dotfiles'
  baseline (via the dotfiles flake input) plus infra's private modules and
  host config.

## Migration safety

The deploy sequencing is the only critical bit:

> **Do not deploy dotfiles' baseline ada to the real machine before infra's
> ada is wired up.** A deploy from dotfiles after the strip would remove
> samba, ftp, local-llm, agent-vms (the *invocation*; the module is still
> imported but `enable` defaults to `false`), the kibana stack, and the
> coder-provisioner user from the running host.

Recommended order:

1. **Infra side first** (out of scope here, done in a `wt add`-created
   worktree of `~/src/infra`): add modules, host config, and re-encrypted
   secret; build infra's ada; verify build.
2. **Dotfiles side** (this PR): apply the strip; verify
   `nix build .#nixosConfigurations.ada.config.system.build.toplevel`
   still builds.
3. **First deploy after the strip** must come from infra, not dotfiles.

The dotfiles PR is safe to merge before the infra side is deployed, as long
as no one runs a dotfiles → ada deploy in the gap. Note this in the PR
description.

## Verification (dotfiles side)

After the strip:
- `nix build .#nixosConfigurations.ada.config.system.build.toplevel` — must
  succeed.
- `nix build .#nixosConfigurations.flamme.config.system.build.toplevel` — must
  still succeed (sanity check on the `modules/nixos/all.nix` changes).
- `nix flake check` — passes.
- `nix fmt` — clean.
- Visual scan of `hosts/nixos/ada/default.nix` — no leftover references to
  removed modules or `age.secrets.ada-samba-passwords`.

## Future follow-ups (not in this design)

- **Per-user samba secrets** (existing project memory): happens on infra side
  now, since the samba module lives there.
- **Complete move of ada to infra**: drop `nixosConfigurations.ada`,
  `hosts/nixos/ada/`, and the rmlint overlay from dotfiles; accept that
  recovery requires infra checkout. The split here makes that a small,
  mechanical change rather than a rewrite.
