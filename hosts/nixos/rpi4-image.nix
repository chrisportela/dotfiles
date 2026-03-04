{
  inputs,
  nixpkgs,
  system ? "aarch64-linux",
  overlays ? [ ],
  ...
}:
nixpkgs.lib.nixosSystem {
  inherit system;

  specialArgs = { inherit system inputs overlays; };

  modules = [
    ../../modules/nixos/hardware/rpi4.nix
    "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
    ../../modules/nixos/nixpkgs.nix
    (
      { ... }:
      {
        system.stateVersion = "25.11";
      }
    )
  ];
}
