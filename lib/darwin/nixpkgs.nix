{ lib, pkgs, config, ... }:
{
  imports = [ ../nixos/modules/nixpkgs.nix ];

  config = {

    nix = {
      package = pkgs.nixVersions.nix_2_31;
      settings = {
        sandbox = false; # Even relaxed prevents HM builds - https://github.com/NixOS/nix/issues/4119 (2020)
        trusted-users = [
          "root"
          "@admin"
        ];
      };
    };
  };
}
