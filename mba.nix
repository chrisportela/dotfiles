{ lib, config, pkgs, ... }:
let
  nixLocalVM = {
    systems = [ "x86_64-linux" "aarch64-linux" ];
    sshUser = "cmp";
    maxJobs = 10;
    hostName = "nix-builder";
    speedFactor = 10;
    supportedFeatures = [ ];
  };
  nixServer = {
    systems = [ "x86_64-linux" "aarch64-linux" ];
    sshUser = "cmp";
    maxJobs = 20;
    hostName = "nix.gorgon-basilisk.ts.net";
    speedFactor = 100;
    supportedFeatures = [ ];
  };
in
{
  imports = [ ./lib/nixos/darwin.nix ];

  nix = {
    distributedBuilds = true;
    settings.extra-platforms = [ "aarch64-darwin" ];
    buildMachines = [ nixLocalVM ];
  };

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 4;
}
