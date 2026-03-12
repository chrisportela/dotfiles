#!/usr/bin/env nix
#!nix shell --ignore-environment nixpkgs#cacert nixpkgs#nix nixpkgs#bash nixpkgs#git nixpkgs#curl nixpkgs#jq nixpkgs#gnused nixpkgs#coreutils --command bash

set -euo pipefail

version=$(curl -s https://api.github.com/repos/openclaw/openclaw/releases/latest | jq -r '.tag_name | ltrimstr("v")')
echo "Latest version: $version"

current=$(sed -nE 's/.*version = "([^"]+)".*/\1/p' pkgs/openclaw.nix)
echo "Current version: $current"

if [ "$version" = "$current" ]; then
  echo "Already up to date."
  exit 0
fi

echo "Updating $current -> $version"

src_hash=$(nix hash convert --to sri --hash-algo sha256 \
  "$(nix-prefetch-url --unpack "https://github.com/openclaw/openclaw/archive/refs/tags/v${version}.tar.gz" 2>/dev/null)")

sed -i "s|version = \"$current\"|version = \"$version\"|" pkgs/openclaw.nix
sed -i "s|hash = \"sha256-[^\"]*\"|hash = \"$src_hash\"|" pkgs/openclaw.nix

# Get new pnpmDepsHash by setting a dummy hash and capturing the correct one
sed -i 's|pnpmDepsHash = "sha256-[^"]*"|pnpmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="|' pkgs/openclaw.nix
git add pkgs/openclaw.nix
pnpm_hash=$( (nix build --no-link ".#openclaw" 2>&1 || true) \
  | sed -nE 's/.*got: *(sha256-[A-Za-z0-9+/=-]+).*/\1/p' | head -1)

if [ -n "$pnpm_hash" ]; then
  sed -i "s|pnpmDepsHash = \"sha256-[^\"]*\"|pnpmDepsHash = \"$pnpm_hash\"|" pkgs/openclaw.nix
  echo "Updated pnpmDepsHash to $pnpm_hash"
else
  echo "Warning: could not determine new pnpmDepsHash" >&2
fi

echo "Updated openclaw to $version"
