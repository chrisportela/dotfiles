# opencode

Packages opencode from source using vendored copies of opencode's first-party
nix expressions, tracking releases independently of nixpkgs.

## Layout

- `package.nix` — pins `version` + `srcHash`, fetches the source, wires the
  vendored expressions together.
- `node_modules.nix` — vendored from upstream `nix/node_modules.nix`, adapted
  to take `src`, `version`, and `hash` as arguments instead of deriving them
  from the checked-out tree at eval time (that eval-time derivation of
  `src`/`version` is import-from-derivation, which `nix flake check` and
  Hydra's evaluator forbid — the reason these files are vendored at all).
- `opencode.nix` — vendored from upstream `nix/opencode.nix`, unchanged except
  `node_modules` is a required argument.
- `hashes.json` — upstream's `nix/hashes.json`, copied verbatim. Our
  `node_modules` FOD reproduces upstream's output exactly, so their published
  per-platform hashes apply directly.

## Updating

Run from the repo root:

```bash
./pkgs/opencode/update.sh
```

The script bumps `version`, refreshes `hashes.json` from the new tag, captures
the new `srcHash` via a build-failure scrape, warns if upstream's
`nix/node_modules.nix` or `nix/opencode.nix` changed between releases (the
vendored copies must then be re-synced by hand), and finishes with a
verification build.

## Dependencies

All build dependencies (bun, models-dev, ripgrep, etc.) come from
nixpkgs-unstable, resolved automatically by `callPackage`.
