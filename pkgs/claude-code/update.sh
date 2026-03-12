#!/usr/bin/env nix
#!nix shell --ignore-environment nixpkgs#cacert nixpkgs#nodejs nixpkgs#nix nixpkgs#bash nixpkgs#git nixpkgs#curl nixpkgs#jq nixpkgs#gnused nixpkgs#coreutils --command bash

set -euo pipefail

pkg=pkgs/claude-code/package.nix

version=$(npm view @anthropic-ai/claude-code version)
echo "Latest version: $version"

current=$(sed -nE 's/.*version = "([^"]+)".*/\1/p' "$pkg")
echo "Current version: $current"

if [ "$version" = "$current" ]; then
  echo "Already up to date."
  exit 0
fi

echo "Updating $current -> $version"

src_hash=$(nix hash convert --to sri --hash-algo sha256 \
  "$(nix-prefetch-url --unpack "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz" 2>/dev/null)")

sed -i "s|version = \"$current\"|version = \"$version\"|" "$pkg"
sed -i "s|hash = \"sha256-[^\"]*\"|hash = \"$src_hash\"|" "$pkg"

# Generate new package-lock.json
tmp=$(mktemp -d)
curl -sL "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz" | tar xz -C "$tmp" --strip-components=1
cd "$tmp" && npm install --package-lock-only --ignore-scripts 2>/dev/null && cd -
cp "$tmp/package-lock.json" pkgs/claude-code/package-lock.json
rm -rf "$tmp"

# Get new npmDepsHash by setting a dummy hash and capturing the correct one
sed -i 's|npmDepsHash = "sha256-[^"]*"|npmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="|' "$pkg"
git add "$pkg" pkgs/claude-code/package-lock.json
npm_hash=$( (NIXPKGS_ALLOW_UNFREE=1 nix build --no-link ".#claude-code" 2>&1 || true) \
  | sed -nE 's/.*got: *(sha256-[A-Za-z0-9+/=-]+).*/\1/p' | head -1)

if [ -n "$npm_hash" ]; then
  sed -i "s|npmDepsHash = \"sha256-[^\"]*\"|npmDepsHash = \"$npm_hash\"|" "$pkg"
  echo "Updated npmDepsHash to $npm_hash"
else
  echo "Warning: could not determine new npmDepsHash" >&2
fi

echo "Updated claude-code to $version"
