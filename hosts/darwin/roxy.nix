# Roxy-specific overrides: nodejs version, nix registry/nixPath, and gid for nixbld.
{ inputs, pkgs, ... }:
{
  ids.gids.nixbld = 350;

  nixpkgs.overlays = [
    (final: prev: {
      nodejs = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.system}.nodejs_20;
    })
  ];

  nix = {
    registry.nixpkgs.flake = inputs.nixpkgs-unstable;
    registry.nixos.flake = inputs.nixpkgs;
    registry.nixos-unstable.flake = inputs.nixpkgs-unstable;
    registry.nixpkgs-unstable.flake = inputs.nixpkgs-unstable;

    nixPath = [
      "nixpkgs=${inputs.nixpkgs-unstable}"
      "nixos=${inputs.nixpkgs}"
      "nixpkgs-unstable=${inputs.nixpkgs-unstable}"
      "nixos-unstable=${inputs.nixpkgs-unstable}"
      "/nix/var/nix/profiles/per-user/root/channels"
    ];
  };
}
