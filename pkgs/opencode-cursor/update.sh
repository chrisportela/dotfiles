#!/usr/bin/env nix
#!nix shell --ignore-environment nixpkgs#cacert nixpkgs#nodejs nixpkgs#nix nixpkgs#bash nixpkgs#git nixpkgs#curl nixpkgs#jq nixpkgs#gnused nixpkgs#gnutar nixpkgs#xz nixpkgs#gzip nixpkgs#coreutils --command bash

set -euo pipefail

pkg=pkgs/opencode-cursor/package.nix
owner=Nomadcxx
repo=opencode-cursor

# Get latest commit on main
commit=$(curl -s "https://api.github.com/repos/$owner/$repo/commits/main" \
  | jq -r '{sha: .sha, date: .commit.committer.date}')
rev=$(echo "$commit" | jq -r '.sha')
date=$(echo "$commit" | jq -r '.date' | cut -dT -f1)

current_rev=$(sed -nE 's/.*rev = "([^"]+)".*/\1/p' "$pkg")
if [ "$rev" = "$current_rev" ]; then
  echo "Already up to date at $rev"
  exit 0
fi

# Get version from upstream package.json
upstream_version=$(curl -sL "https://raw.githubusercontent.com/$owner/$repo/$rev/package.json" | jq -r '.version')
version="${upstream_version}-unstable-${date}"
echo "Updating to $version ($rev)"

# Prefetch source
src_hash=$(nix hash convert --to sri --hash-algo sha256 \
  "$(nix-prefetch-url --unpack "https://github.com/$owner/$repo/archive/${rev}.tar.gz" 2>/dev/null)")

sed -i "s|version = \"[^\"]*\"|version = \"$version\"|" "$pkg"
sed -i "s|rev = \"[^\"]*\"|rev = \"$rev\"|" "$pkg"
sed -i "s|hash = \"sha256-[^\"]*\"|hash = \"$src_hash\"|" "$pkg"

# Generate correct package-lock.json by running npm install
tmp=$(mktemp -d)
curl -sL "https://github.com/$owner/$repo/archive/${rev}.tar.gz" | tar xz -C "$tmp" --strip-components=1
cd "$tmp" && npm install --package-lock-only --ignore-scripts 2>/dev/null && cd -
cp "$tmp/package-lock.json" pkgs/opencode-cursor/package-lock.json
rm -rf "$tmp"

# Get new npmDepsHash by setting a dummy hash and capturing the correct one
sed -i 's|npmDepsHash = "sha256-[^"]*"|npmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="|' "$pkg"
git add "$pkg" pkgs/opencode-cursor/package-lock.json
npm_hash=$( (nix build --no-link ".#opencode-cursor" 2>&1 || true) \
  | sed -nE 's/.*got: *(sha256-[A-Za-z0-9+/=-]+).*/\1/p' | head -1)

if [ -n "$npm_hash" ]; then
  sed -i "s|npmDepsHash = \"sha256-[^\"]*\"|npmDepsHash = \"$npm_hash\"|" "$pkg"
  echo "Updated npmDepsHash to $npm_hash"
else
  echo "Warning: could not determine new npmDepsHash" >&2
fi

echo "Updated opencode-cursor to $version"
