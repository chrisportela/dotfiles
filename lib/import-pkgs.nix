# Build pkgs/pkgsUnstable for a given system with overlays and unfree. Called as:
# importPkgs = (import ./lib/import-pkgs.nix) { inherit self nixpkgs nixpkgs-unstable inputs; };
{
  self,
  nixpkgs,
  nixpkgs-unstable,
  inputs,
  config ? { },
  allowUnfree ? [ ],
  allowUnfreePredicate ? null,
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
      cliclick
    ]);
  unfreePredicate =
    if allowUnfreePredicate == null then
      (pkg: builtins.elem (nixpkgs.lib.getName pkg) allowUnfree)
    else
      allowUnfreePredicate;
in
rec {
  pkgsUnstable = import nixpkgs-unstable {
    inherit system;
    config = {
      allowUnfreePredicate = unfreePredicate;
    }
    // config;
    overlays = overlays';
  };
  pkgs = import nixpkgs {
    inherit system;
    config = {
      allowUnfreePredicate = unfreePredicate;
    }
    // config;
    overlays = [
      (final: prev: { pkgsUnstable = pkgsUnstable; })
    ]
    ++ overlays';
  };
}
