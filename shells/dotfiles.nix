{ pkgs }:
pkgs.mkShellNoCC {
  packages = (
    with pkgs;
    [
      cachix
      nixd
      nixfmt-rfc-style
      shellcheck
      shfmt
    ]
  );
}
