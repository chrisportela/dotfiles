# opencode

Packages opencode from source using opencode's own first-party nix expressions
(`nix/node_modules.nix`, `nix/opencode.nix`), tracking releases independently of nixpkgs.

## Updating

Run from the repo root:

```bash
./pkgs/opencode/update.sh
```

The script fetches the latest release from GitHub, then rebuilds twice to capture
the correct `srcHash` and `nodeModulesHash`.

## How it works

Fetches the opencode source for the pinned `version` and calls opencode's own
`nix/node_modules.nix` + `nix/opencode.nix` directly from the fetched src. The
`node_modules` FOD builds with `--frozen-lockfile` removed so that nixpkgs' bun can
re-resolve the lockfile (opencode's `packageManager` field sometimes pins a slightly newer
bun than nixpkgs ships; without this the FOD errors before emitting the expected hash).
`nodeModulesHash` is therefore our own captured value (not opencode's `nix/hashes.json`),
but is fully reproducible and self-healing via `update.sh`.

The overlay in `overlays/default.nix` ensures we use our version unless nixpkgs ships
a newer one.

## Dependencies

All build dependencies (bun, models-dev, ripgrep, etc.) come from nixpkgs-unstable,
resolved automatically by `callPackage` against opencode's own expressions.
