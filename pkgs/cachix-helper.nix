{
  pkgs,
  lib,
  stdenv,
  cachix,
  nix,
}:
let
  cachixRepo = "chrisportela-dotfiles";
  cachixArgs = lib.concatStringsSep " " [
    "--compression-level 9"
    "--compression-method zstd"
    "--jobs 4"
  ];
  nixBin = "${nix}/bin/nix";
  cachixBin = "${cachix}/bin/cachix";
  hmConfig = "cmp";
in
(pkgs.writeShellScriptBin "cachix-helper" ''
  set -eu
  SYSTEM="${stdenv.system}"
  if [ -n "''${1-}" ]; then
    SYSTEM="$1"
  fi
  echo "#### Building HM"
  if command -v home-manager 1>/dev/null 2>&1; then
    home-manager build --flake .#${hmConfig}
  else
    ${nixBin} build .#legacyPackages.$SYSTEM.homeConfigurations.${hmConfig}.activationPackage
  fi
  rm result-hm-cmp || true
  mv result result-hm-cmp
  ${cachixBin} push ${cachixArgs} ${cachixRepo} result-hm-cmp
  ${cachixBin} pin ${cachixRepo} --keep-revisions 2 home-manager-$SYSTEM result-hm-cmp

  echo "#### Building shells"
  ${nixBin} build --out-link result-shell-dotfiles .#devShells.$SYSTEM.dotfiles
  ${cachixBin} push ${cachixArgs} ${cachixRepo} result-shell-dotfiles
  ${cachixBin} pin ${cachixRepo} --keep-revisions 2 shell-dotfiles-$SYSTEM result-shell-dotfiles

  ${nixBin} build --out-link result-shell-devops .#devShells.$SYSTEM.devops
  ${cachixBin} push ${cachixArgs} ${cachixRepo} result-shell-devops
  ${cachixBin} pin ${cachixRepo} --keep-revisions 2 shell-devops-$SYSTEM result-shell-devops

  ${nixBin} build --out-link result-shell-dev .#devShells.$SYSTEM.dev
  ${cachixBin} push ${cachixArgs} ${cachixRepo} result-shell-dev
  ${cachixBin} pin ${cachixRepo} --keep-revisions 2 shell-dev-$SYSTEM result-shell-dev

  echo "#### Finished!"
'')
// {

  meta = with lib; {
    description = "A helper script for using Cachix";
    license = licenses.mit;
    maintainers = with maintainers; [ "chrisportela" ];
    platforms = platforms.unix;
  };
}
