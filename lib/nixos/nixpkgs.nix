{ lib, config, pkgs, inputs, nixpkgs ? inputs.nixpkgs, overlays, ... }: with lib; {
  nix = {
    package = mkDefault pkgs.nixVersions.nix_2_16;
    registry.nixpkgs.flake = nixpkgs;

    settings = {
      keep-outputs = mkDefault true;
      keep-derivations = mkDefault true;
      experimental-features = [ "nix-command" "flakes" ];
      sandbox = true;
      trusted-users = mkDefault [ "root" "@wheel" ];
      extra-trusted-public-keys = mkDefault [
        "binarycache.cp-mba.local:xH/m5WHjOty8a0/n27WSKGhNC0eDf/HX6GREG+G6czM="
        "cache.cp-mba.local-1:YJIH05Ett5Tcq2eEyfroindEQdpwBG5F5f7ztZ+gFCw="
      ];
    };
  };

  nixpkgs = {
    inherit overlays;
  };
}
