# CLAUDE.md

## Rules

- Modules must live in their own directory with a `default.nix` and a `README.md` that explains
  purpose, options, and dependencies. Refer to the module's README for details rather than
  duplicating documentation here.

## Commands

```bash
nix build .                    # Test full config builds
nix run . -- -b backup         # Apply home-manager config
nix build .#nixosConfigurations.ada.config.system.build.toplevel  # Build NixOS for ada
nix build .#darwinConfigurations.roxy.system                      # Build Darwin for roxy
```

## Layout

- **flake.nix** — Entry point. Defines NixOS, Darwin, and home-manager configs for multiple hosts.
- **modules/** — Nix modules split by target: `home/`, `nixos/`, `darwin/`. Each module has its own README.
- **hosts/** — Per-machine config: `nixos/ada/`, `nixos/flamme/`, `darwin/mba.nix`, `darwin/roxy.nix`.
- **shells/** — Dev shells: dotfiles, dev, devops, react-native.
- **pkgs/** — Custom packages (callPackage pattern).
- **overlays/** — Nixpkgs overlays applied via `lib/import-pkgs.nix`.
- **lib/** — Helpers: `import-pkgs.nix`, `simple-home-config.nix`, `ssh-keys.nix`.
- **templates/** — Flake templates (nextjs, react-native) with their own CLAUDE.md files.
- **secrets/** — Agenix-encrypted secrets.

## Key patterns

- Home modules use enable flags: `chrisportela.desktop`, `chrisportela.experiment`, `chrisportela.coding-agents`.
- `lib/import-pkgs.nix` creates `pkgs`/`pkgsUnstable` with overlays for a given system.
- `lib/simple-home-config.nix` wraps home-manager with feature flags.
- Unfree packages explicitly allowed: terraform, vault-bin, claude-code, xcode.
- Supports x86_64-linux, aarch64-linux, aarch64-darwin.

## Gotchas

- `nix-rosetta-builder` is needed on Darwin hosts for cross-compilation.
- `result-*` symlinks in the root are build artifacts that keep built results from being garbage collected by Nix. They are not tracked in git.
