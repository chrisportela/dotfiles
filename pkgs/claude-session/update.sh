#!/usr/bin/env nix
#!nix shell --ignore-environment nixpkgs#cacert nixpkgs#bash nixpkgs#curl nixpkgs#nix nixpkgs#gnused nixpkgs#coreutils nixpkgs#jq --command bash

set -euo pipefail

pkg=pkgs/claude-session/package.nix

version=$(curl -s https://registry.npmjs.org/claude-session-skill/latest | jq -r .version)
current=$(sed -nE 's/.*version = "([^"]+)".*/\1/p' "$pkg")
echo "Latest version: $version"
echo "Current version: $current"

if [ "$version" = "$current" ]; then
  echo "Already up to date."
  exit 0
fi

echo "Updating $current -> $version"

url="https://registry.npmjs.org/claude-session-skill/-/claude-session-skill-$version.tgz"
store_path=$(nix-prefetch-url "$url" --name "claude-session-skill-$version.tgz" 2>/dev/null)
hash=$(nix hash convert --to sri --hash-algo sha256 "$store_path")

sed -i "s|version = \"$current\"|version = \"$version\"|" "$pkg"
sed -i "s|hash = \"sha256-[^\"]*\"|hash = \"$hash\"|" "$pkg"

echo "Updated claude-session to $version"
