{ lib, config, pkgs, ... }:
let
  nixLocalVM = {
    systems = [ "x86_64-linux" "aarch64-linux" ];
    maxJobs = 4;
    protocol = "ssh-ng";
    sshUser = "cmp";
    hostName = "nix-builder";
    speedFactor = 10;
    supportedFeatures = [ ];
  };
  nixServer = {
    systems = [ "x86_64-linux" "aarch64-linux" ];
    maxJobs = 20;
    protocol = "ssh-ng";
    sshUser = "cmp";
    hostName = "nix.gorgon-basilisk.ts.net";
    speedFactor = 1;
    supportedFeatures = [ ];
  };
in
{
  imports = [
    ../common.nix
    ../nixpkgs.nix
  ];

  nix = {
    settings = {
      connect-timeout = "5";
    };
  };

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 4;
}
