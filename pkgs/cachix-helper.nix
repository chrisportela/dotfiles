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
  hmConfig = "cmp";
in
# shells = ["dotfiles", "dev", "devops"];
(pkgs.writeShellScriptBin "cachix-helper" ''
  set -eu
  echo "#### Building HM"
  if command -v tailscale 1>/dev/null 2>&1; then
    home-manager build --flake .#${hmConfig}
  else
    nix build .#legacyPackages.${stdenv.system}.homeConfigurations.${hmConfig}.activationPackage
  fi
  rm result-hm-cmp || true
  mv result result-hm-cmp
  cachix push ${cachixArgs} ${cachixRepo} result-hm-cmp
  cachix pin ${cachixRepo} home-manager-${stdenv.system} result-hm-cmp

  echo "#### Building shells"
  nix build --out-link result-shell-dotfiles .#devShells.${stdenv.system}.dotfiles
  cachix push ${cachixArgs} ${cachixRepo} result-shell-dotfiles
  cachix pin ${cachixRepo} shell-dotfiles-${stdenv.system} result-shell-dotfiles

  nix build --out-link result-shell-devops .#devShells.${stdenv.system}.devops
  cachix push ${cachixArgs} ${cachixRepo} result-shell-devops
  cachix pin ${cachixRepo} shell-devops-${stdenv.system} result-shell-devops

  nix build --out-link result-shell-dev .#devShells.${stdenv.system}.dev
  cachix push ${cachixArgs} ${cachixRepo} result-shell-dev
  cachix pin ${cachixRepo} shell-dev-${stdenv.system} result-shell-dev

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
