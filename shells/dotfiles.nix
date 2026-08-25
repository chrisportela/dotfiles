{ pkgs }:
pkgs.mkShellNoCC {
  packages = (
    with pkgs;
    [
      cachix
      nixd
      nixfmt
      shellcheck
      shfmt
      agenix
      # scripts/ci/*.sh run inside this shell on the Forgejo runners
      git
      jq
      curl
      actionlint
    ]
  );
}
