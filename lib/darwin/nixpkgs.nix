{ lib, pkgs, config, ... }:
{
  imports = [ ../nixos/modules/nixpkgs.nix ];

  options.allowedUnfree = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
  };

  config = {
    nixpkgs.config.allowUnfreePredicate = lib.mkForce (
      p: builtins.elem (lib.getName p) config.allowedUnfree
    );

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
