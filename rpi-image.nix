{config, lib, pkgs, ...}: (((import ./lib/nixos/hardware/rpi4.nix) {inherit config lib pkgs; } ) // {
  nixpkgs.hostPlatform = "aarch64-linux";

  system = {
    copySystemConfiguration = true;
    # includeBuildDependencies = true;
  };

  nix = {
    settings.auto-optimise-store = true;
  };
})
