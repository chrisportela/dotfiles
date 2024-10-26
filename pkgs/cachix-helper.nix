{ pkgs, lib, stdenv, cachix, nix }:
let
  cachixRepo = "chrisportela-dotfiles";
  cachixArgs = lib.concatStringsSep " " [ "--compression-level 9" "--compression-method zstd" "--jobs 4" ];
  hmConfig = "cmp";
  # shells = ["dotfiles", "dev", "devops"];
in (pkgs.writeShellScriptBin "cachix-helper" ''
  set -eu
  echo "#### Building HM"
  if command -v tailscale 1>/dev/null 2>&1; then
    home-manager build --flake .#${hmConfig}
  else
    nix build .#legacyPackages.${stdenv.system}.homeConfigurations.${hmConfig}.activationPackage
  fi
  cachix push ${cachixArgs} ${cachixRepo} result
  cachix pin ${cachixRepo} home-manager-${stdenv.system} result

  echo "#### Building shells"
  nix build .#devShells.${stdenv.system}.dotfiles
  cachix push ${cachixArgs} ${cachixRepo} result
  cachix pin ${cachixRepo} shell-dotfiles-${stdenv.system} result

  nix build .#devShells.${stdenv.system}.devops
  cachix push ${cachixArgs} ${cachixRepo} result
  cachix pin ${cachixRepo} shell-devops-${stdenv.system} result

  nix build .#devShells.${stdenv.system}.dev
  cachix push ${cachixArgs} ${cachixRepo} result
  cachix pin ${cachixRepo} shell-dev-${stdenv.system} result

  echo "#### Finished!"
'') //{

  meta = with lib; {
    description = "A helper script for using Cachix";
    license = licenses.mit;
    maintainers = with maintainers; [ "chrisportela" ];
    platforms = platforms.unix;
  };
}
