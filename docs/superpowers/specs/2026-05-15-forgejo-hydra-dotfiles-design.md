# Forgejo + Hydra Wiring for dotfiles

**Date:** 2026-05-15
**Status:** Draft
**Scope:** Make this `dotfiles` flake build on the existing Cafecito Cloud Hydra and push results to the existing Attic caches.

## Summary

Push the `dotfiles` flake to the Forgejo instance on liara, register a declarative Hydra project for it, and expose a `hydraJobs` output covering the hosts, custom packages, dev shells, and home activations that should be cached. All upstream pieces (Forgejo, Hydra, build farm, Attic post-build-hook) already exist and serve the `infra` repo today; this is purely additive on the dotfiles side.

## Goals

- `git push liara main` puts the flake on `git.cafecito.cloud/cmp/dotfiles`.
- Hydra evaluates the flake on every push to `main` (300s check interval matching infra's defaults) and builds the `hydraJobs` manifest.
- Builds dispatch to the existing remote builders (`ada`, `lucy`) over the tailnet.
- Every successful build is pushed to both Attic caches (`cache.cafecito.cloud` on liara, `nix.cafecito.cloud` on ciri) via Hydra's existing post-build-hook.
- Adding or changing jobsets later is a single-file edit to `hydra/spec.nix` followed by a push.

## Non-Goals (Deferred)

- Substituter / trusted-key wiring in `flake.nix` or `modules/nixos/nixpkgs.nix`. Host substituters are managed via global config on each machine.
- Darwin builds (`darwinConfigurations.{mba,roxy,lux}`). No Darwin builder exists; covering them needs a separate hardware/CI design.
- `aarch64-linux` builds (`nixosConfigurations.rpi4`, the `pi` sdImage). No `aarch64-linux` builder.
- Disk-image jobs (`installer-iso`, `pi`). Multi-GB outputs are build-on-demand.
- Pull-request / non-main-branch jobsets. The shape supports this trivially (one more entry in `spec.nix`) but isn't part of the initial scope.
- A `cmp-dotfiles` Forgejo Actions workflow. Hydra is the build path; Actions can stay reserved for non-build automation if/when needed.

## Existing Infrastructure (background)

These pieces already run on liara and are documented in `~/src/infra`:

- **Forgejo** at `git.cafecito.cloud` (`cafecito.git` module, HTTP_PORT 3400, SSH 2222).
- **Hydra** at `hydra.cafecito.cloud` (`cafecito.hydra` module, port 3300).
  - Build farm: `ada.gorgon-basilisk.ts.net` (x86_64-linux, kvm, 8 jobs) and `lucy.gorgon-basilisk.ts.net:2222` (WSL2, x86_64-linux, 4 jobs).
  - `allowed-uris` already includes `https://git.cafecito.cloud/`.
  - `post-build-hook` pushes every completed build to two Attic targets: `liara` (`http://127.0.0.1:8092`) and `ciri` (`https://nix.cafecito.cloud`).
- **Attic** caches `cache.cafecito.cloud` (liara, local disk) and `nix.cafecito.cloud` (ciri, B2-backed).
- A working declarative-jobset pattern in `infra/hydra/spec.nix`, evaluated against `infra/flake.nix`'s `hydraJobs`.

The dotfiles flake already has a `liara` git remote pointing at `ssh://forgejo@git.cafecito.cloud:2222/cmp/dotfiles.git`, configured but never pushed.

## Architecture

```
┌────────────────────────────────────────────────────────────────┐
│  dev box                                                       │
│  └─ git push liara main ────┐                                  │
│                             ▼                                  │
│  ┌─────────────────────────────────┐                           │
│  │ Forgejo (liara)                 │                           │
│  │   git.cafecito.cloud            │                           │
│  │   repo: cmp/dotfiles            │                           │
│  └──────────────┬──────────────────┘                           │
│                 │ git+ssh fetch (every 300s)                   │
│                 ▼                                              │
│  ┌─────────────────────────────────┐                           │
│  │ Hydra (liara)                   │                           │
│  │   project: cmp-dotfiles         │                           │
│  │   evaluates hydra/spec.nix      │                           │
│  │   → jobset "main"               │                           │
│  │   → builds hydraJobs            │                           │
│  └──────────────┬──────────────────┘                           │
│                 │ ssh nix-builder@{ada,lucy}                   │
│                 ▼                                              │
│  ┌─────────────────────────────────┐                           │
│  │ Build farm                      │                           │
│  │   ada.gorgon-basilisk.ts.net    │                           │
│  │   lucy.gorgon-basilisk.ts.net   │                           │
│  └──────────────┬──────────────────┘                           │
│                 │ post-build-hook (existing)                   │
│                 ▼                                              │
│  ┌─────────────────────────────────┐                           │
│  │ Attic                           │                           │
│  │   cache.cafecito.cloud (liara)  │                           │
│  │   nix.cafecito.cloud  (ciri)    │                           │
│  └─────────────────────────────────┘                           │
└────────────────────────────────────────────────────────────────┘
```

Everything below the Hydra box already exists. New work is the top half: pushing this flake and registering a Hydra project.

## Files

| File | Change | Purpose |
|---|---|---|
| `flake.nix` | **Edit** — add `hydraJobs` to the per-system outputs | Tell Hydra what to build |
| `hydra/spec.nix` | **Add** | Declarative jobset definition Hydra reads |
| `docs/hydra.md` | **Add** | One-time bootstrap recipe + day-2 ops runbook for this project |

No changes to `nixConfig`, `modules/nixos/nixpkgs.nix`, flake inputs, or git remotes.

## `hydraJobs` manifest

Shape: `hydraJobs.<group>.<name>.<system> = derivation`. Restricted to `x86_64-linux` (the only architecture the build farm covers).

```nix
hydraJobs =
  let
    sys = "x86_64-linux";
    pkgs = self.packages.${sys};
    legacy = self.legacyPackages.${sys};
  in
  {
    # Full NixOS system closures.
    hosts = {
      ada.${sys}    = self.nixosConfigurations.ada.config.system.build.toplevel;
      flamme.${sys} = self.nixosConfigurations.flamme.config.system.build.toplevel;
    };

    # Custom packages from pkgs/.
    # Excluded:
    #   - pi (rpi4 sdImage, aarch64-linux, no builder)
    #   - cliclick / peekaboo* / swift6 (aarch64-darwin only)
    #   - default (alias for cmp home activation; covered by homeActivations)
    packages = {
      terraform.${sys}        = pkgs.terraform;
      cachix-helper.${sys}    = pkgs.cachix-helper;
      attic-helper.${sys}     = pkgs.attic-helper;
      rmlint.${sys}           = pkgs.rmlint;
      openclaw.${sys}         = pkgs.openclaw;
      opencode-cursor.${sys}  = pkgs.opencode-cursor;
      claude-code.${sys}      = pkgs.claude-code;
      cursor-agent.${sys}     = pkgs.cursor-agent;
      opencode.${sys}         = pkgs.opencode;
      context7.${sys}         = pkgs.context7;
      plane-mcp-server.${sys} = pkgs.plane-mcp-server;
      setup-envrc.${sys}      = pkgs.setup-envrc;
      update.${sys}           = pkgs.update;
      wt.${sys}               = pkgs.wt;
      llmfit.${sys}           = pkgs.llmfit;
    };

    # Dev shells. `nix build` on a shell builds its inputs closure.
    devShells = {
      dotfiles.${sys}     = self.devShells.${sys}.dotfiles;
      dev.${sys}          = self.devShells.${sys}.dev;
      devops.${sys}       = self.devShells.${sys}.devops;
      react-native.${sys} = self.devShells.${sys}.react-native;
    };

    # home-manager activation packages.
    # Hydra job names disallow `@`, so flatten `cmp@ada` → `cmp-at-ada`.
    # The legacyPackages.homeConfigurations names stay as-is.
    homeActivations = {
      cmp.${sys}               = legacy.homeConfigurations.cmp.activationPackage;
      nixos.${sys}             = legacy.homeConfigurations.nixos.activationPackage;
      cmp-at-ada.${sys}        = legacy.homeConfigurations."cmp@ada".activationPackage;
      cmp-at-flamme.${sys}     = legacy.homeConfigurations."cmp@flamme".activationPackage;
      deck-at-steamdeck.${sys} = legacy.homeConfigurations."deck@steamdeck".activationPackage;
    };
  };
```

Expected job count: 2 hosts + 15 packages + 4 dev shells + 5 home activations = **26 derivations**, all `x86_64-linux`.

## `hydra/spec.nix`

Mirrors `infra/hydra/spec.nix`. Plain `import <nixpkgs>` because the file only emits a `spec.json` Hydra reads — it doesn't build anything from the flake's pinned inputs.

```nix
# Declarative Hydra project spec for cmp/dotfiles.
#
# Hydra evaluates this file (via nix-build) and reads the resulting JSON
# to create/update the project's jobsets. The owning project is configured
# (one-time, via the Hydra UI) with:
#
#   declarative.spec  = "hydra/spec.nix"
#   declarative.type  = "git"
#   declarative.value = "git+ssh://forgejo@git.cafecito.cloud:2222/cmp/dotfiles.git main"
#
# After bootstrap, all jobset changes happen by editing this file and
# pushing to main — Hydra picks up changes on its next evaluation of
# the project's hidden `.jobsets` jobset.
#
# Build manually: `nix-build hydra/spec.nix` → produces a `spec.json`.
let
  pkgs = import <nixpkgs> { };

  flakeUri = "git+ssh://forgejo@git.cafecito.cloud:2222/cmp/dotfiles.git";

  defaults = {
    enabled = 1;
    hidden = false;
    checkinterval = 300;
    schedulingshares = 100;
    enableemail = false;
    emailoverride = "";
    keepnr = 5;
    type = "flake";
  };

  jobsets = {
    main = defaults // {
      description = "cmp dotfiles: hosts + packages + devshells + home activations (main)";
      flake = "${flakeUri}?ref=main";
    };
  };
in
pkgs.writeText "spec.json" (builtins.toJSON jobsets)
```

## Bootstrap (one-time)

After the files above land on `main`, three manual steps:

### 1. Push the flake to Forgejo

```sh
git push liara main
```

If `cmp/dotfiles` doesn't exist on Forgejo yet, create it via the Forgejo UI first (or rely on push-create — `cafecito.git.createRepoOnPushUser` is enabled on liara).

### 2. Confirm Hydra can fetch from Forgejo as it does for `infra`

Hydra fetches `infra` from the same Forgejo over `git+ssh://forgejo@git.cafecito.cloud:2222`, so the `hydra` user's SSH key, `known_hosts`, and Forgejo deploy-key wiring are already configured. The plan stage will verify this concretely (e.g., `ssh liara sudo -u hydra git ls-remote git+ssh://forgejo@git.cafecito.cloud:2222/cmp/dotfiles.git`) and add a deploy key only if needed for the new repo.

### 3. Create the Hydra project (via Hydra UI)

Log in to <https://hydra.cafecito.cloud> as an admin user, then **Admin → Create project**:

- **Identifier:** `cmp-dotfiles`
- **Display name:** `cmp dotfiles`
- **Enabled:** yes
- **Declarative spec file:** `hydra/spec.nix`
- **Declarative input type:** `Git checkout`
- **Declarative input value:** `git+ssh://forgejo@git.cafecito.cloud:2222/cmp/dotfiles.git main`

Hydra creates the hidden `.jobsets` jobset, evaluates `hydra/spec.nix`, and materializes the `main` jobset.

### 4. Smoke check

```sh
ssh liara sudo -u hydra hydra-eval-jobset cmp-dotfiles main
ssh liara journalctl -fu hydra-evaluator -u hydra-queue-runner
```

Then visit `https://hydra.cafecito.cloud/jobset/cmp-dotfiles/main`. Confirm jobs queue, dispatch to ada/lucy, succeed, and the post-build-hook pushes to both Attic caches.

## Testing & verification

- **Local eval before bootstrap:** `nix flake check --no-build` and `nix flake show` must succeed against the dotfiles flake before pushing — Hydra's eval will hit the same code path.
- **Spec sanity:** `nix-build hydra/spec.nix --no-out-link` from a checkout must emit a `spec.json` whose `main.flake` field matches the Forgejo SSH URI.
- **Build smoke:** `nix build .#hydraJobs.packages.wt.x86_64-linux` and `nix build .#hydraJobs.hosts.ada.x86_64-linux` succeed locally on ada.
- **Hydra dashboard:** after bootstrap, every job in the manifest reaches `Succeeded` at least once within the first eval cycle (~5 minutes per `checkinterval`).
- **Cache push:** after a successful build, `attic info liara:main <store-path>` (or fetching the same path from `https://nix.cafecito.cloud/main/`) shows the path is present.

## Risks & open questions

- **Hydra deploy-key on the `cmp/dotfiles` Forgejo repo.** Most likely already covered by the same SSH key Hydra uses for `infra`. The plan stage must verify (`ssh liara sudo -u hydra git ls-remote ...`) before declaring the bootstrap done.
- **`pkgs.update`** wraps an `update.sh` script with a shebang that invokes `nix shell`. Building it under Hydra is fine, but `update.sh` itself is meant for interactive use; nothing in the manifest depends on running it.
- **`flake.nix nixConfig` extra-substituters.** Hydra's evaluator runs with a fixed substituter set; the flake's declared substituters are advisory. This shouldn't break the eval, but worth watching the evaluator log on the first run.
- **`allowed-uris`** already covers `github:`, `gitlab:`, and `https://git.cafecito.cloud/`. The dotfiles flake's inputs are all GitHub-backed (`github:nixos/nixpkgs/...`, `github:nix-community/...`, etc.), so no additional allowed-uri entries are needed.
- **Eval load.** Each `nixosConfigurations` toplevel pulls a fair chunk of the module tree. Two hosts is fine; if we add many more later, we may want to split jobsets to bound evaluator memory.
