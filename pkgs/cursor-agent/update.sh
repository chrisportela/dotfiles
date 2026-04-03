#!/usr/bin/env nix
#!nix shell --ignore-environment nixpkgs#cacert nixpkgs#bash nixpkgs#curl nixpkgs#nix nixpkgs#gnused nixpkgs#coreutils nixpkgs#gawk nixpkgs#gnugrep --command bash

set -euo pipefail

pkg=pkgs/cursor-agent/package.nix

# Get latest release identifier from cursor.com
release=$(curl -s https://cursor.com/install | grep -oP "lab/\K[^/]+")
echo "Latest release: $release"

if [[ "$release" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}-[a-f0-9]+$ ]]; then
  timestamp=$(echo "$release" | cut -d"-" -f1 | tr "." "-")
  version="0-unstable-$timestamp"
else
  version="$release"
fi

current=$(sed -nE 's/.*version = "([^"]+)".*/\1/p' "$pkg")
echo "Latest version: $version"
echo "Current version: $current"

if [ "$version" = "$current" ]; then
  echo "Already up to date."
  exit 0
fi

echo "Updating $current -> $version"

# Capture old release identifier before making changes
old_release=$(sed -nE 's|.*lab/([^/]+)/.*|\1|p' "$pkg" | head -1)

# Update version
sed -i "s|version = \"$current\"|version = \"$version\"|" "$pkg"

# Update all URLs with new release
sed -i "s|lab/$old_release/|lab/$release/|g" "$pkg"

# Update hashes for each platform
declare -A platforms=( [x86_64-linux]="linux/x64" [aarch64-linux]="linux/arm64" [x86_64-darwin]="darwin/x64" [aarch64-darwin]="darwin/arm64" )

for platform in "${!platforms[@]}"; do
  url="https://downloads.cursor.com/lab/$release/${platforms[$platform]}/agent-cli-package.tar.gz"
  echo "Prefetching $platform..."
  store_path=$(nix-prefetch-url "$url" --name "cursor-agent-$version" 2>/dev/null)
  hash=$(nix hash convert --to sri --hash-algo sha256 "$store_path")

  # Replace the hash on the line following this platform's URL
  awk -v path="${platforms[$platform]}" -v newhash="$hash" '
    found && /hash =/ { sub(/hash = "sha256-[^"]*"/, "hash = \"" newhash "\""); found=0 }
    /url =/ && index($0, path) { found=1 }
    { print }
  ' "$pkg" > "$pkg.tmp" && mv "$pkg.tmp" "$pkg"
done

echo "Updated cursor-agent to $version"
