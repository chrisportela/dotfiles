#!/usr/bin/env nix
#!nix shell --ignore-environment nixpkgs#cacert nixpkgs#nodejs nixpkgs#git nixpkgs#nix-update nixpkgs#nix nixpkgs#gnused nixpkgs#findutils nixpkgs#bash --command bash

set -euo pipefail

version=$(npm view @anthropic-ai/claude-code version)

# Update version and hashes
AUTHORIZED=1 NIXPKGS_ALLOW_UNFREE=1 nix-update --flake claude-code --version="$version" --generate-lockfile

# nix-update can't update package-lock.json along with npmDepsHash
# TODO: Remove this workaround if nix-update can update package-lock.json along with npmDepsHash.
(nix build --no-link --expr '(builtins.getFlake (toString ./.)).packages.${builtins.currentSystem}.claude-code.npmDeps.overrideAttrs { outputHash = ""; outputHashAlgo = "sha256"; }' 2>&1 || true) \
| sed -nE '$s/ *got: *(sha256-[A-Za-z0-9+/=-]+).*/\1/p' \
| xargs -I{} sed -i 's|npmDepsHash = "sha256-[^"]*";|npmDepsHash = "{}";|' pkgs/claude-code/package.nix
