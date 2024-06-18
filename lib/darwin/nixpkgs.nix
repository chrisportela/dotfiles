{ lib, config, pkgs, inputs, nixpkgs, overlays, ... }: with lib; {
  nix = {
    package = mkDefault pkgs.nixVersions.nix_2_19;
    registry.nixpkgs.flake = nixpkgs;
    configureBuildUsers = true;

    settings = {
      keep-outputs = mkDefault true;
      keep-derivations = mkDefault true;
      experimental-features = [ "nix-command" "flakes" ];
      sandbox = false;
      trusted-users = mkDefault [ "root" "@admin" ];
      extra-trusted-public-keys = mkDefault [
        "binarycache.cp-mba.local:xH/m5WHjOty8a0/n27WSKGhNC0eDf/HX6GREG+G6czM="
        "cache.cp-mba.local-1:YJIH05Ett5Tcq2eEyfroindEQdpwBG5F5f7ztZ+gFCw="
      ];

    };

    linux-builder.enable = true;
  };

  nixpkgs = {
    inherit overlays;
  };

  services.nix-daemon.enable = true;
}
