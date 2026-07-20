{
  pkgs,
  lib,
  stdenv,
  cachix,
  nix,
  cachixRepo ? "chrisportela-dotfiles",
  keepRevisions ? 2,
}:
let
  cachixArgs = lib.concatStringsSep " " [
    "--compression-level 9"
    "--compression-method zstd"
    "--jobs 4"
  ];
  nixBin = "${nix}/bin/nix";
  cachixBin = "${cachix}/bin/cachix";
in
(pkgs.writeShellScriptBin "cachix-helper" ''
  set -eu
  SYSTEM="${stdenv.system}"
  if [ -n "''${1-}" ]; then
    SYSTEM="$1"
  fi
  echo "Using SYSTEM=$SYSTEM"

  if [ ! -f flake.nix ]; then
    echo "Error: flake.nix not found. Run this script from the flake root." >&2
    exit 1
  fi

  echo "#### Building cache-targets"
  ${nixBin} build --out-link result-cache-targets .#packages.$SYSTEM.cache-targets
  ${cachixBin} push ${cachixArgs} ${cachixRepo} result-cache-targets

  echo "#### Pinning targets"
  for entry in result-cache-targets/*; do
    name="$(basename "$entry")"
    target="$(readlink -f "$entry")"
    ${cachixBin} pin ${cachixRepo} --keep-revisions ${toString keepRevisions} "$name-$SYSTEM" "$target"
  done

  echo "#### Finished!"
'')
// {

  meta = with lib; {
    description = "Helper script for building and pushing cache-targets to Cachix";
    license = licenses.mit;
    maintainers = [ ];
    mainProgram = "cachix-helper";
    platforms = platforms.unix;
  };
}
