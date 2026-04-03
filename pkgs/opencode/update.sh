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

# Step 1: Get new src hash
sed -i 's|hash = "sha256-[^"]*"|hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="|' "$PKG_FILE"
git add "$PKG_FILE"
src_hash=$( (nix build --no-link ".#opencode" 2>&1 || true) \
  | sed -nE 's/.*got: *(sha256-[A-Za-z0-9+/=_-]+).*/\1/p' | head -1)

if [ -z "$src_hash" ]; then
  echo "Error: could not determine new src hash" >&2
  exit 1
fi
sed -i "s|hash = \"sha256-[^\"]*\"|hash = \"$src_hash\"|" "$PKG_FILE"
echo "Updated src hash to $src_hash"

# Step 2: Get new node_modules outputHash
sed -i 's|outputHash = "sha256-[^"]*"|outputHash = "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB="|' "$PKG_FILE"
git add "$PKG_FILE"
modules_hash=$( (nix build --no-link ".#opencode" 2>&1 || true) \
  | sed -nE 's/.*got: *(sha256-[A-Za-z0-9+/=_-]+).*/\1/p' | head -1)

if [ -n "$modules_hash" ]; then
  sed -i "s|outputHash = \"sha256-[^\"]*\"|outputHash = \"$modules_hash\"|" "$PKG_FILE"
  echo "Updated node_modules outputHash to $modules_hash"
else
  echo "Warning: could not determine new node_modules outputHash" >&2
fi

echo "Updated opencode to $version"
