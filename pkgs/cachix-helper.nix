{
  pkgs,
  lib,
  stdenv,
  cachix,
  nix,
  cachixRepo ? "chrisportela-dotfiles",
  hmConfig ? "cmp",
  keepRevisions ? 2,
  shellNames ? [ "dotfiles" "dev" "devops" "react-native" ],
}:
let
  cachixArgs = lib.concatStringsSep " " [
    "--compression-level 9"
    "--compression-method zstd"
    "--jobs 4"
  ];
  nixBin = "${nix}/bin/nix";
  cachixBin = "${cachix}/bin/cachix";

  shellBlocks = lib.concatMapStringsSep "\n\n" (name: ''
    echo "#### Building shell: ${name}"
    ${nixBin} build --out-link result-shell-${name} .#devShells.$SYSTEM.${name}
    ${cachixBin} push ${cachixArgs} ${cachixRepo} result-shell-${name}
    ${cachixBin} pin ${cachixRepo} --keep-revisions ${toString keepRevisions} shell-${name}-$SYSTEM result-shell-${name}
  '') shellNames;
in
(pkgs.writeShellScriptBin "cachix-helper" ''
  set -eu
  SYSTEM="${stdenv.system}"
  if [ -n "''${1-}" ]; then
    SYSTEM="$1"
  fi
  echo "Using SYSTEM=$SYSTEM"

  if [ ! -f flake.nix ]; then
    echo "Error: flake.nix not found. Run this script from the flake root." >&2
    exit 1
  fi

  echo "#### Building HM"
  if command -v home-manager 1>/dev/null 2>&1; then
    home-manager build --flake .#${hmConfig}
  else
    ${nixBin} build .#legacyPackages.$SYSTEM.homeConfigurations.${hmConfig}.activationPackage
  fi
  rm result-hm-${hmConfig} || true
  mv result result-hm-${hmConfig}
  ${cachixBin} push ${cachixArgs} ${cachixRepo} result-hm-${hmConfig}
  ${cachixBin} pin ${cachixRepo} --keep-revisions ${toString keepRevisions} home-manager-$SYSTEM result-hm-${hmConfig}

  echo "#### Building shells"
  ${shellBlocks}

  echo "#### Finished!"
'')
// {

  meta = with lib; {
    description = "Helper script for building and pushing home-manager and dev shells to Cachix";
    license = licenses.mit;
    maintainers = [ ];
    mainProgram = "cachix-helper";
    platforms = platforms.unix;
  };
}
