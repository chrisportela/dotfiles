{ inputs, nixosModules, overlays, system ? "aarch64-linux", ... }: inputs.nixpkgs.lib.nixosSystem {
  inherit system;

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
