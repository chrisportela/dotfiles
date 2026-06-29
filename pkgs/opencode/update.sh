#!/usr/bin/env nix
#!nix shell --ignore-environment nixpkgs#cacert nixpkgs#nix nixpkgs#bash nixpkgs#git nixpkgs#curl nixpkgs#jq nixpkgs#gnused nixpkgs#coreutils --command bash

set -euo pipefail

PKG_FILE="pkgs/opencode/package.nix"

version=$(curl -s https://api.github.com/repos/anomalyco/opencode/releases/latest | jq -r '.tag_name | ltrimstr("v")')
echo "Latest version: $version"

current=$(sed -nE 's/.*version = "([^"]+)".*/\1/p' "$PKG_FILE")
echo "Current version: $current"

if [ "$version" = "$current" ]; then
  echo "Already up to date."
  exit 0
fi

echo "Updating $current -> $version"

# Update version
sed -i "s|version = \"$current\"|version = \"$version\"|" "$PKG_FILE"

# Step 1: Get new srcHash
sed -i 's|srcHash = "sha256-[^"]*"|srcHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="|' "$PKG_FILE"
git add "$PKG_FILE"
src_hash=$( (nix build --no-link ".#opencode" 2>&1 || true) \
  | sed -nE 's/.*got: *(sha256-[A-Za-z0-9+/=_-]+).*/\1/p' | head -1)

if [ -z "$src_hash" ]; then
  echo "Error: could not determine new srcHash" >&2
  exit 1
fi
sed -i "s|srcHash = \"sha256-[^\"]*\"|srcHash = \"$src_hash\"|" "$PKG_FILE"
echo "Updated srcHash to $src_hash"

# Step 2: Get new nodeModulesHash
# The node_modules FOD builds using opencode's own nix/node_modules.nix (--frozen-lockfile
# removed so nixpkgs bun works). A hash mismatch emits "got: sha256-..." as expected.
sed -i 's|nodeModulesHash = "sha256-[^"]*"|nodeModulesHash = "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB="|' "$PKG_FILE"
git add "$PKG_FILE"
modules_hash=$( (nix build --no-link ".#opencode" 2>&1 || true) \
  | sed -nE 's/.*got: *(sha256-[A-Za-z0-9+/=_-]+).*/\1/p' | head -1)

if [ -n "$modules_hash" ]; then
  sed -i "s|nodeModulesHash = \"sha256-[^\"]*\"|nodeModulesHash = \"$modules_hash\"|" "$PKG_FILE"
  echo "Updated nodeModulesHash to $modules_hash"
else
  echo "Warning: could not determine new nodeModulesHash" >&2
fi

echo "Updated opencode to $version"
