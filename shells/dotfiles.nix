{ pkgs }: pkgs.mkShell {
  packages = (with pkgs; [
    cachix
    nixd
    nixpkgs-fmt
    shellcheck
    shfmt
  ]);
}
