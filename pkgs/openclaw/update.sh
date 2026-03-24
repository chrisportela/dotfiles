#!/usr/bin/env nix
#!nix shell --ignore-environment nixpkgs#cacert nixpkgs#nix nixpkgs#bash nixpkgs#git nixpkgs#curl nixpkgs#jq nixpkgs#gnused nixpkgs#coreutils --command bash

set -euo pipefail

PKG_FILE="pkgs/openclaw/default.nix"

tag_version=$(curl -s https://api.github.com/repos/openclaw/openclaw/releases/latest | jq -r '.tag_name | ltrimstr("v")')
echo "Latest tag version: $tag_version"

current=$(sed -nE 's/.*tagVersion = "([^"]+)".*/\1/p' "$PKG_FILE")
echo "Current tag version: $current"

if [ "$tag_version" = "$current" ]; then
  echo "Already up to date."
  exit 0
fi

# Derive display version (drop any suffix like "-1")
display_version=$(echo "$tag_version" | sed 's/-[0-9]*$//')
echo "Updating $current -> $tag_version (display: $display_version)"

# Update tagVersion and version
sed -i "s|tagVersion = \"$current\"|tagVersion = \"$tag_version\"|" "$PKG_FILE"
sed -i "s|version = \"[^\"]*\"|version = \"$display_version\"|" "$PKG_FILE"

# Step 1: Get new src hash
# Set a dummy src hash to force a mismatch, then capture the correct one
sed -i 's|hash = "sha256-[^"]*"|hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="|' "$PKG_FILE"
git add "$PKG_FILE"
src_hash=$( (nix build --no-link ".#openclaw" 2>&1 || true) \
  | sed -nE 's/.*got: *(sha256-[A-Za-z0-9+/=_-]+).*/\1/p' | head -1)

if [ -z "$src_hash" ]; then
  echo "Error: could not determine new src hash" >&2
  exit 1
fi
sed -i "s|hash = \"sha256-[^\"]*\"|hash = \"$src_hash\"|" "$PKG_FILE"
echo "Updated src hash to $src_hash"

# Step 2: Get new pnpmDepsHash
# Set a dummy pnpm hash to force a mismatch, then capture the correct one
sed -i 's|pnpmDepsHash = "sha256-[^"]*"|pnpmDepsHash = "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB="|' "$PKG_FILE"
git add "$PKG_FILE"
pnpm_hash=$( (nix build --no-link ".#openclaw" 2>&1 || true) \
  | sed -nE 's/.*got: *(sha256-[A-Za-z0-9+/=_-]+).*/\1/p' | head -1)

if [ -n "$pnpm_hash" ]; then
  sed -i "s|pnpmDepsHash = \"sha256-[^\"]*\"|pnpmDepsHash = \"$pnpm_hash\"|" "$PKG_FILE"
  echo "Updated pnpmDepsHash to $pnpm_hash"
else
  echo "Warning: could not determine new pnpmDepsHash" >&2
fi

echo "Updated openclaw to $display_version (tag: $tag_version)"
