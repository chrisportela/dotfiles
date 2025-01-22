{ pkgs }:
pkgs.mkShell {
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
