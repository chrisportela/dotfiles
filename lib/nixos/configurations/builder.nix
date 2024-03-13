{ nixpkgs, nixosModules, system ? "aarch64-linux", ... }:
nixpkgs.lib.nixosSystem {
  inherit system;

  specialArgs = {
    inherit nixpkgs;
    overlays = [ ];
  };

  modules = [
    "${nixpkgs}/nixos/modules/virtualisation/qemu-vm.nix"
    nixosModules.common
    nixosModules.nixpkgs
    nixosModules.network
    nixosModules.openssh
    {
      chrisportela.network = {
        enable = true;
        tailscale = false;
        mDNS = false;
        speedtest-utils = false;
      };
    }
  ];
}
