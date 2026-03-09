#!/usr/bin/env nix
#!nix shell --ignore-environment nixpkgs#nix-update nixpkgs#nix nixpkgs#bash nixpkgs#git --command bash

set -euo pipefail

nix-update --flake opencode-cursor --version=branch
