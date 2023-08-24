{inputs, nixosModules, overlays, ...}: inputs.nixpkgs.lib.nixosSystem {
  system = "aarch64-linux";
  specialArgs = {
    inherit inputs overlays;
    nixpkgs = inputs.nixpkgs;
  };
  modules = [
    "${inputs.nixpkgs}/nixos/modules/virtualisation/qemu-vm.nix"
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
