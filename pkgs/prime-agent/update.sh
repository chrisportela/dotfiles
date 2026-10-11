#!/usr/bin/env nix
#!nix shell --ignore-environment nixpkgs#cacert nixpkgs#bash nixpkgs#nix nixpkgs#curl nixpkgs#jq nixpkgs#gnused nixpkgs#coreutils nixpkgs#gnugrep nixpkgs#git --command bash

set -euo pipefail

pkg=pkgs/prime-agent/default.nix
dummy="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

# /releases/latest skips prereleases; only stable releases publish the
# -src.tar.gz asset this package builds from.
tag=$(curl -s https://api.github.com/repos/PrimeIntellect-ai/prime-agent/releases/latest | jq -r '.tag_name')
version="${tag#v}"
echo "Latest version: $version"

current=$(sed -nE 's/^  version = "([^"]+)";/\1/p' "$pkg")
echo "Current version: $current"

if [ "$version" = "$current" ]; then
  echo "Already up to date."
  exit 0
fi

echo "Updating $current -> $version"
sed -i "s|^  version = \"$current\";|  version = \"$version\";|" "$pkg"

# Source hash (fetchzip, stripRoot = false: hash of the unpacked tree).
url="https://github.com/PrimeIntellect-ai/prime-agent/releases/download/v${version}/prime-agent-${version}-src.tar.gz"
src_hash=$(nix hash convert --to sri --hash-algo sha256 "$(nix-prefetch-url --unpack "$url")")
sed -i "s|^    hash = \"sha256-[^\"]*\";|    hash = \"$src_hash\";|" "$pkg"

# Cargo vendor hash: set a dummy, build, and take the hash Nix reports.
sed -i "s|^  cargoHash = \"sha256-[^\"]*\";|  cargoHash = \"$dummy\";|" "$pkg"
git add "$pkg"
cargo_hash=$( (nix build --no-link ".#prime-agent" 2>&1 || true) \
  | sed -nE 's/.*got: *(sha256-[A-Za-z0-9+/=-]+).*/\1/p' | head -1)

if [ -n "$cargo_hash" ]; then
  sed -i "s|^  cargoHash = \"$dummy\";|  cargoHash = \"$cargo_hash\";|" "$pkg"
  echo "Updated cargoHash to $cargo_hash"
else
  echo "Warning: could not determine new cargoHash" >&2
fi

echo "Updated prime-agent to $version"
