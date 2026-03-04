# Build pkgs/pkgsUnstable for a given system with overlays and unfree. Called as:
# importPkgs = (import ./lib/import-pkgs.nix) { inherit self nixpkgs nixpkgs-unstable inputs; };
{
  self,
  nixpkgs,
  nixpkgs-unstable,
  inputs,
  allowUnfree ? [ ],
  overlays ? [ ],
}:
system:
let
  overlays' =
    overlays
    ++ (with (import ../overlays/default.nix { inherit self inputs; }); [
      rust
      rustToolchain
      deploy-rs
      terraform
      setup-envrc
      opencode-cursor
    ]);
  unfreePredicate = (pkg: builtins.elem (nixpkgs.lib.getName pkg) allowUnfree);
in
rec {
  pkgsUnstable = import nixpkgs-unstable {
    inherit system;
    config.allowUnfreePredicate = unfreePredicate;
    overlays = overlays';
  };
  pkgs = import nixpkgs {
    inherit system;
    config.allowUnfreePredicate = unfreePredicate;
    overlays = [
      (final: prev: { pkgsUnstable = pkgsUnstable; })
    ]
    ++ overlays';
  };
}
