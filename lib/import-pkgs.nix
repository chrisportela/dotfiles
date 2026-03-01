# Build pkgs/pkgsUnstable for a given system with overlays and unfree. Called as:
# importPkgs = (import ./lib/import-pkgs.nix) { inherit self nixpkgs nixpkgs-unstable inputs; };
{ self, nixpkgs, nixpkgs-unstable, inputs }:
system:
let
  overlays = with (import ../overlays/default.nix { inherit self inputs; }); [
    rust
    rustToolchain
    deploy-rs
    terraform
    setup-envrc
    opencode-cursor
  ];
  unfreePredicate = (
    pkg:
    builtins.elem (nixpkgs.lib.getName pkg) [
      "terraform"
      "vault-bin"
      "claude-code"
    ]
  );
  nixosUnstablePkgs = import inputs.nixpkgs-unstable {
    inherit system;
    config.allowUnfreePredicate = unfreePredicate;
  };
in
rec {
  pkgsUnstable = import nixpkgs-unstable {
    inherit system;
    config.allowUnfreePredicate = unfreePredicate;
    overlays = overlays ++ [
      (final: prev: {
        claude-code = self.packages.${system}.claude-code;
      })
    ];
  };
  pkgs = import nixpkgs {
    inherit system;
    config.allowUnfreePredicate = unfreePredicate;
    overlays = overlays ++ [
      (final: prev: {
        pkgsUnstable = pkgsUnstable;
      })
      (final: prev: {
        claude-code = self.packages.${system}.claude-code;
      })
    ];
  };
}
