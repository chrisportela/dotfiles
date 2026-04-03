# opencode

Override of the upstream nixpkgs `opencode` package to track the latest version independently.

## Updating

Run from the repo root:

```bash
./pkgs/opencode/update.sh
```

The script fetches the latest release from GitHub, then rebuilds twice to capture
the correct src hash and node_modules output hash.

## How it works

Uses `overrideAttrs` on the upstream nixpkgs `opencode` derivation — only overrides
`version`, `src`, and `node_modules` hash. The full build machinery (bun, models-dev,
shell completions) stays upstream.

The overlay in `overlays/default.nix` ensures we use our version unless nixpkgs
ships a newer one.

## Dependencies

All dependencies come from upstream nixpkgs (bun, models-dev, ripgrep, etc.).
