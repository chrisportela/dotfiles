{ config, lib, pkgs, overlays ? [ ], ... }: {
  # Pending https://github.com/NixOS/nixpkgs/issues/55674
  options.allowedUnfree = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
  };

  config = {
    nixpkgs.config.allowUnfreePredicate = lib.mkForce (p: builtins.elem (lib.getName p) config.allowedUnfree);
    nix = {
      package = lib.mkDefault pkgs.nixVersions.latest;
      # registry.nixpkgs.flake = nixpkgs;

      settings = {
        keep-outputs = lib.mkDefault true;
        keep-derivations = lib.mkDefault true;
        experimental-features = lib.mkDefault [ "nix-command" "flakes" "auto-allocate-uids" "configurable-impure-env" ];
        sandbox = lib.mkDefault true;
        trusted-users = lib.mkDefault [ "root" "@wheel" ];
        extra-substituters = lib.mkDefault [
          "https://chrisportela-dotfiles.cachix.org"
        ];
        extra-trusted-public-keys = lib.mkDefault [
          # TODO: Rotate & pass via arg?
          "binarycache.cp-mba.local:xH/m5WHjOty8a0/n27WSKGhNC0eDf/HX6GREG+G6czM="
          "cache.cp-mba.local-1:YJIH05Ett5Tcq2eEyfroindEQdpwBG5F5f7ztZ+gFCw="
          "chrisportela-dotfiles.cachix.org-1:e3UVWzLbmS6YLEUaY1BQt124GENPRF74YMgwV/6+Li4="
        ];
      };
    };

    nixpkgs = {
      inherit overlays;
    };
  };
}
