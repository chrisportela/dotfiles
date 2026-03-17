# Roxy-specific overrides: nodejs version, nix registry/nixPath, and gid for nixbld.
{ inputs, pkgs, ... }:
{
  ids.gids.nixbld = 350;

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

    settings = {
      extra-substituters = [
        "https://virby-nix-darwin.cachix.org"
        "https://chrisportela-dotfiles.cachix.org"
        "https://nix-community.cachix.org"
      ];
      extra-trusted-public-keys = [
        "virby-nix-darwin.cachix.org-1:z9GiEZeBU5bEeoDQjyfHPMGPBaIQJOOvYOOjGMKIlLo="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "chrisportela-dotfiles.cachix.org-1:e3UVWzLbmS6YLEUaY1BQt124GENPRF74YMgwV/6+Li4="
      ];
    };
  };
}
