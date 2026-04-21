#!/usr/bin/env nix
#!nix shell --ignore-environment nixpkgs#cacert nixpkgs#bash nixpkgs#nix nixpkgs#curl nixpkgs#jq nixpkgs#gnused nixpkgs#coreutils nixpkgs#gnugrep nixpkgs#gawk --command bash

set -euo pipefail

PKG_FILE="pkgs/plane-mcp-server/default.nix"

# Fetch latest versions from PyPI
sdk_version=$(curl -s https://pypi.org/pypi/plane_sdk/json | jq -r '.info.version')
mcp_version=$(curl -s https://pypi.org/pypi/plane_mcp_server/json | jq -r '.info.version')
echo "Latest plane-sdk: $sdk_version"
echo "Latest plane-mcp-server: $mcp_version"

current_sdk=$(awk '/pname = "plane_sdk"/{found=1} found && /version =/{gsub(/.*version = "|";$/,""); print; exit}' "$PKG_FILE")
current_mcp=$(awk '/pname = "plane_mcp_server"/{found=1} found && /version =/{gsub(/.*version = "|";$/,""); print; exit}' "$PKG_FILE")
echo "Current plane-sdk: $current_sdk"
echo "Current plane-mcp-server: $current_mcp"

if [ "$sdk_version" = "$current_sdk" ] && [ "$mcp_version" = "$current_mcp" ]; then
  echo "Already up to date."
  exit 0
fi

# Update plane-sdk version and hash
if [ "$sdk_version" != "$current_sdk" ]; then
  echo "Updating plane-sdk $current_sdk -> $sdk_version"
  # Update version (first occurrence)
  sed -i "0,/version = \"$current_sdk\"/s|version = \"$current_sdk\"|version = \"$sdk_version\"|" "$PKG_FILE"

  # Prefetch new hash
  sdk_url=$(curl -s https://pypi.org/pypi/plane_sdk/"$sdk_version"/json | jq -r '.urls[] | select(.packagetype == "sdist") | .url')
  sdk_store=$(nix-prefetch-url "$sdk_url" 2>/dev/null)
  sdk_hash=$(nix hash convert --to sri --hash-algo sha256 "$sdk_store")

  # Replace the first hash (plane-sdk's)
  awk -v newhash="$sdk_hash" '
    !done && /hash = "sha256-/ { sub(/hash = "sha256-[^"]*"/, "hash = \"" newhash "\""); done=1 }
    { print }
  ' "$PKG_FILE" > "$PKG_FILE.tmp" && mv "$PKG_FILE.tmp" "$PKG_FILE"
  echo "Updated plane-sdk hash to $sdk_hash"
fi

# Update plane-mcp-server version and hash
if [ "$mcp_version" != "$current_mcp" ]; then
  echo "Updating plane-mcp-server $current_mcp -> $mcp_version"
  # Update version (the one after plane_mcp_server pname)
  sed -i "/pname = \"plane_mcp_server\"/,/version =/ s|version = \"$current_mcp\"|version = \"$mcp_version\"|" "$PKG_FILE"

  # Prefetch new hash
  mcp_url=$(curl -s https://pypi.org/pypi/plane_mcp_server/"$mcp_version"/json | jq -r '.urls[] | select(.packagetype == "sdist") | .url')
  mcp_store=$(nix-prefetch-url "$mcp_url" 2>/dev/null)
  mcp_hash=$(nix hash convert --to sri --hash-algo sha256 "$mcp_store")

  # Replace the second hash (plane-mcp-server's)
  awk -v newhash="$mcp_hash" '
    /hash = "sha256-/ { count++ }
    count == 2 && /hash = "sha256-/ { sub(/hash = "sha256-[^"]*"/, "hash = \"" newhash "\""); count++ }
    { print }
  ' "$PKG_FILE" > "$PKG_FILE.tmp" && mv "$PKG_FILE.tmp" "$PKG_FILE"
  echo "Updated plane-mcp-server hash to $mcp_hash"
fi

echo "Updated plane-mcp-server package"
