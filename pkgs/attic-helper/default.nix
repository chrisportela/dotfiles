{
  pkgs,
  lib,
  stdenv,
  attic-client,
  nix,
  hmConfig ? "cmp",
  shellNames ? [
    "dotfiles"
    "dev"
    "devops"
    # Disabled: Requires too much space in cache (40gb+)
    # "react-native"
  ],
}:
let
  nixBin = "${nix}/bin/nix";
  atticBin = "${attic-client}/bin/attic";

  shellBlocks = lib.concatMapStringsSep "\n\n" (name: ''
    echo "#### Building shell: ${name}"
    run ${nixBin} build --out-link result-shell-${name} .#devShells.$SYSTEM.${name}
    run ${atticBin} push --jobs 4 $EXTRA_ARGS "$CACHE" result-shell-${name}
  '') shellNames;
in
(pkgs.writeShellScriptBin "attic-helper" ''
  set -eu

  run() {
    echo "+ $*" >&2
    "$@"
  }

  usage() {
    cat <<'USAGE' >&2
  Usage: attic-helper <CACHE> [SYSTEM] [--all]

    <CACHE>   Attic cache to push to, e.g. "ciri:main"
    [SYSTEM]  Nix system (defaults to current host)
    --all     Push every path, ignoring the upstream cache filter
  USAGE
  }

  ALL=0
  CACHE=""
  SYSTEM="${stdenv.system}"
  positional=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --all|-a) ALL=1; shift ;;
      -h|--help) usage; exit 0 ;;
      --) shift; break ;;
      -*) echo "Unknown flag: $1" >&2; usage; exit 2 ;;
      *)
        case "$positional" in
          0) CACHE="$1"; positional=1 ;;
          1) SYSTEM="$1"; positional=2 ;;
          *) echo "Unexpected arg: $1" >&2; usage; exit 2 ;;
        esac
        shift ;;
    esac
  done

  if [ -z "$CACHE" ]; then
    echo "Error: <CACHE> is required" >&2
    usage
    exit 2
  fi

  EXTRA_ARGS=""
  if [ "$ALL" = 1 ]; then
    EXTRA_ARGS="--ignore-upstream-cache-filter"
  fi

  echo "Using CACHE=$CACHE SYSTEM=$SYSTEM ALL=$ALL"

  if [ ! -f flake.nix ]; then
    echo "Error: flake.nix not found. Run this script from the flake root." >&2
    exit 1
  fi

  echo "#### Building HM"
  if command -v home-manager 1>/dev/null 2>&1; then
    run home-manager build --flake .#${hmConfig}
  else
    run ${nixBin} build .#legacyPackages.$SYSTEM.homeConfigurations.${hmConfig}.activationPackage
  fi
  run rm result-hm-${hmConfig} || true
  run mv result result-hm-${hmConfig}
  run ${atticBin} push --jobs 4 $EXTRA_ARGS "$CACHE" result-hm-${hmConfig}

  echo "#### Building shells"
  ${shellBlocks}

  echo "#### Finished!"
'')
// {

  meta = with lib; {
    description = "Helper script for building and pushing home-manager and dev shells to an Attic cache";
    license = licenses.mit;
    maintainers = [ ];
    mainProgram = "attic-helper";
    platforms = platforms.unix;
  };
}
