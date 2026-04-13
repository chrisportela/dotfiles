#!/usr/bin/env nix
#!nix shell --ignore-environment nixpkgs#cacert nixpkgs#bash nixpkgs#nix nixpkgs#curl nixpkgs#jq nixpkgs#gnused nixpkgs#coreutils nixpkgs#gnugrep --command bash

set -euo pipefail

pkg=pkgs/context7/default.nix

# Get latest MCP release from GitHub
release=$(curl -s https://api.github.com/repos/upstash/context7/releases \
  | jq -r '[.[] | select(.tag_name | startswith("@upstash/context7-mcp@"))][0]')
version=$(echo "$release" | jq -r '.tag_name' | sed 's/@upstash\/context7-mcp@//')
echo "Latest MCP version: $version"

current=$(sed -nE 's/.*version = "([^"]+)".*/\1/p' "$pkg")
echo "Current version: $current"

if [ "$version" = "$current" ]; then
  echo "Already up to date."
  exit 0
fi

echo "Updating $current -> $version"

# Get the commit SHA for the release tag
tag_encoded=$(echo "@upstash/context7-mcp@${version}" | sed 's/@/%40/g; s/\//%2F/g')
rev=$(curl -s "https://api.github.com/repos/upstash/context7/git/ref/tags/${tag_encoded}" | jq -r '.object.sha')
echo "Release commit: $rev"

# Update version and rev
sed -i "s|version = \"$current\"|version = \"$version\"|" "$pkg"
old_rev=$(sed -nE 's/.*rev = "([^"]+)".*/\1/p' "$pkg")
sed -i "s|rev = \"$old_rev\"|rev = \"$rev\"|" "$pkg"

# Update source hash
src_hash=$(nix hash convert --to sri --hash-algo sha256 \
  "$(nix-prefetch-url --unpack "https://github.com/upstash/context7/archive/${rev}.tar.gz" 2>/dev/null)")
sed -i "s|hash = \"sha256-[^\"]*\"|hash = \"$src_hash\"|" "$pkg"

# Update pnpmDeps hash by setting dummy and capturing correct one
sed -i '0,/hash = "sha256-[^"]*"/! { /hash = "sha256-[^"]*"/ s|hash = "sha256-[^"]*"|hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="|; }' "$pkg"
git add "$pkg"
pnpm_hash=$( (nix build --no-link ".#context7" 2>&1 || true) \
  | sed -nE 's/.*got: *(sha256-[A-Za-z0-9+/=-]+).*/\1/p' | head -1)

if [ -n "$pnpm_hash" ]; then
  sed -i "s|hash = \"sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\"|hash = \"$pnpm_hash\"|" "$pkg"
  echo "Updated pnpmDeps hash to $pnpm_hash"
else
  echo "Warning: could not determine new pnpmDeps hash" >&2
fi

echo "Updated context7 to $version"
