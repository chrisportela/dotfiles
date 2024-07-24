{ nixpkgs, nixosModules, system ? "aarch64-linux", ... }:
nixpkgs.lib.nixosSystem {
  inherit system;

  specialArgs = {
    inherit nixpkgs;
    overlays = [ ];
  };

  modules = [
    "${nixpkgs}/nixos/modules/virtualisation/qemu-vm.nix"
    ../modules/common.nix
    ../modules/nixpkgs.nix
    ../modules/network.nix
    ../modules/openssh.nix
    {
      chrisportela.common.enable = true;
      chrisportela.network = {
        enable = true;
        tailscale = false;
        mDNS = false;
        speedtest-utils = false;
      };
    }
  ];
}
