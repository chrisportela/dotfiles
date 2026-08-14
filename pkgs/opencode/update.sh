#!/usr/bin/env nix
#!nix shell --ignore-environment nixpkgs#cacert nixpkgs#nix nixpkgs#bash nixpkgs#git nixpkgs#curl nixpkgs#jq nixpkgs#gnused nixpkgs#coreutils nixpkgs#diffutils --command bash

set -euo pipefail

PKG_DIR="pkgs/opencode"
PKG_FILE="$PKG_DIR/package.nix"
RAW="https://raw.githubusercontent.com/anomalyco/opencode"

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

# node_modules hashes come verbatim from upstream's nix/hashes.json
curl -fsS "$RAW/v$version/nix/hashes.json" -o "$PKG_DIR/hashes.json"
echo "Refreshed hashes.json"

# Get new srcHash
sed -i 's|srcHash = "sha256-[^"]*"|srcHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="|' "$PKG_FILE"
git add "$PKG_DIR"
src_hash=$( (nix build --no-link ".#opencode" 2>&1 || true) \
  | sed -nE 's/.*got: *(sha256-[A-Za-z0-9+/=_-]+).*/\1/p' | head -1)

if [ -z "$src_hash" ]; then
  echo "Error: could not determine new srcHash" >&2
  exit 1
fi
sed -i "s|srcHash = \"sha256-[^\"]*\"|srcHash = \"$src_hash\"|" "$PKG_FILE"
echo "Updated srcHash to $src_hash"

# node_modules.nix and opencode.nix are hand-adapted vendored copies of
# upstream's nix/ expressions; warn when upstream changed them between the
# two releases so the adaptation can be re-synced by hand.
for f in node_modules.nix opencode.nix; do
  if ! diff -q <(curl -fsS "$RAW/v$current/nix/$f") <(curl -fsS "$RAW/v$version/nix/$f") > /dev/null; then
    echo "WARNING: upstream nix/$f changed between v$current and v$version;" >&2
    echo "         review the diff and re-sync the vendored $PKG_DIR/$f" >&2
  fi
done

# Verification build (node_modules FOD hash mismatches surface here)
git add "$PKG_DIR"
nix build --no-link ".#opencode"

echo "Updated opencode to $version"
