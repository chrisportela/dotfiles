{ lib, config, pkgs, ... }:
let
  inherit (pkgs.stdenv) isLinux isDarwin;
in
with lib;
{
  options = { };

  config = {
    nix = (recursiveUpdate
      # Defaults targeting NixOS/Linux
      {
        package = mkDefault pkgs.nixVersions.nix_2_16;

        settings = {
          keep-outputs = mkDefault true;
          keep-derivations = mkDefault true;
          experimental-features = [ "nix-command" "flakes" ];
          sandbox = true;
          trusted-users = mkDefault [ "root" "@wheel" ];
          trusted-public-keys = mkDefault [
            "binarycache.cp-mba.local:xH/m5WHjOty8a0/n27WSKGhNC0eDf/HX6GREG+G6czM="
            "cache.cp-mba.local-1:YJIH05Ett5Tcq2eEyfroindEQdpwBG5F5f7ztZ+gFCw="
          ];
        };
      }
      # macOS defaults
      (optionalAttrs isDarwin {
        configureBuildUsers = true;

        settings = {
          sandbox = "relaxed";
          trusted-users = mkDefault [ "root" "cmp" ];
        };

      })
    );
  };
}
