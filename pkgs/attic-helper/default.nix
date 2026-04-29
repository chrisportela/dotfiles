{
  pkgs,
  lib,
  stdenv,
  attic-client,
  nix,
  atticCache ? "ciri:main",
  hmConfig ? "cmp",
  shellNames ? [
    "dotfiles"
    "dev"
    "devops"
    # Disabled: Requires too much space in cache (40gb+)
    # "react-native"
  ],
}:
let
  atticArgs = lib.concatStringsSep " " [
    "--jobs 4"
  ];
  nixBin = "${nix}/bin/nix";
  atticBin = "${attic-client}/bin/attic";

  shellBlocks = lib.concatMapStringsSep "\n\n" (name: ''
    echo "#### Building shell: ${name}"
    ${nixBin} build --out-link result-shell-${name} .#devShells.$SYSTEM.${name}
    ${atticBin} push ${atticArgs} ${atticCache} result-shell-${name}
  '') shellNames;
in
(pkgs.writeShellScriptBin "attic-helper" ''
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
  ${atticBin} push ${atticArgs} ${atticCache} result-hm-${hmConfig}

  echo "#### Building shells"
  ${shellBlocks}

  echo "#### Finished!"
'')
// {

  meta = with lib; {
    description = "Helper script for building and pushing home-manager and dev shells to an Attic cache";
    license = licenses.mit;
    maintainers = [ ];
    mainProgram = "attic-helper";
    platforms = platforms.unix;
  };
}
