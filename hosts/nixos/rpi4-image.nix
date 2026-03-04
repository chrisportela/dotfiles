{ inputs, nixos, system ? "aarch64-linux", overlays ? [ ], ... }:
nixos.lib.nixosSystem {
  inherit system;

  specialArgs = { inherit system inputs overlays; };

  modules = [
    ../../modules/nixos/hardware/rpi4.nix
    "${nixos}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
    ../../modules/nixos/nixpkgs.nix
  ];
}
