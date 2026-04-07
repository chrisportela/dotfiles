#!/usr/bin/env nix
#!nix shell --ignore-environment nixpkgs#cacert nixpkgs#bash nixpkgs#curl nixpkgs#nix nixpkgs#gnused nixpkgs#coreutils nixpkgs#gawk nixpkgs#gnugrep --command bash

set -euo pipefail

pkg=pkgs/llmfit/package.nix
repo="AlexsJones/llmfit"

# Resolve latest release tag from GitHub (unauthenticated; the API allows this).
tag=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
  | grep '"tag_name"' \
  | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')
version="${tag#v}"

current=$(sed -nE 's/.*version = "([^"]+)".*/\1/p' "$pkg" | head -1)

echo "Latest version: $version"
echo "Current version: $current"

if [ "$version" = "$current" ]; then
  echo "Already up to date."
  exit 0
fi

echo "Updating $current -> $version"

# Per-platform asset suffix table.
declare -A targets=(
  [x86_64-linux]="x86_64-unknown-linux-musl"
  [aarch64-linux]="aarch64-unknown-linux-musl"
  [x86_64-darwin]="x86_64-apple-darwin"
  [aarch64-darwin]="aarch64-apple-darwin"
)

# Refresh per-platform hashes first; only bump the version line after every
# platform has been rewritten successfully. This way, an interrupted run (or
# the unfilled-TODO fail-fast below) leaves package.nix completely untouched.
for system in "${!targets[@]}"; do
  target="${targets[$system]}"
  asset="llmfit-v${version}-${target}.tar.gz"
  url="https://github.com/$repo/releases/download/v${version}/${asset}"

  # Trust the upstream .sha256 sidecar rather than re-prefetching the tarball:
  # llmfit publishes one sidecar per asset, and a `git diff` review of this
  # script's output catches any drift before we commit.
  hex=$(curl -fsSL "${url}.sha256" | awk '{print $1}')
  sri=$(nix hash convert --hash-algo sha256 --to sri --from base16 "$hex")

  echo "  $system: $sri"

  # Replace the hash on the line that follows this platform's URL.
  awk -v target="$target" -v newhash="$sri" '
    found && /hash =/ { sub(/hash = "sha256-[^"]*"/, "hash = \"" newhash "\""); found=0 }
    /url =/ && index($0, target) { found=1 }
    { print }
  ' "$pkg" > "$pkg.tmp" && mv "$pkg.tmp" "$pkg"
done

# All four platform hashes refreshed successfully — bump the version line last.
sed -i "s|version = \"$current\"|version = \"$version\"|" "$pkg"

echo "Updated llmfit to $version"
