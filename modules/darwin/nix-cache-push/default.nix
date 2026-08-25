# Auto-push every locally-built store path to the niks3 cache via nix's
# post-build-hook. Darwin analog of the infra repo's NixOS
# cafecito.nixCachePush module. See README.md for purpose, options, and
# dependencies.
#
# NOTE: nix.settings.post-build-hook is a SINGLE value — nothing else may
# claim it on hosts where this is enabled.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.chrisportela.nix-cache-push;

  # The hook runs synchronously inside every `nix build`; it must never
  # wedge builds. Push failures (cache down, token missing) are warnings,
  # and a hard timeout guards against a hung upload.
  postBuildHook = pkgs.writeShellScript "niks3-post-build-hook" ''
    set -uf
    [ -n "''${OUT_PATHS:-}" ] || exit 0
    export NIKS3_SERVER_URL=${lib.escapeShellArg cfg.serverUrl}
    export NIKS3_AUTH_TOKEN_FILE=${lib.escapeShellArg cfg.tokenFile}
    # shellcheck disable=SC2086 # OUT_PATHS is a space-separated list
    ${pkgs.coreutils}/bin/timeout ${toString cfg.pushTimeout} \
      ${lib.getExe' cfg.package "niks3"} push $OUT_PATHS \
      || echo "warning: niks3 push failed for $OUT_PATHS" >&2
  '';
in
{
  options.chrisportela.nix-cache-push = {
    enable = lib.mkEnableOption "automatic niks3 push of locally-built store paths";

    package = lib.mkOption {
      type = lib.types.package;
      default = inputs.niks3.packages.${pkgs.stdenv.hostPlatform.system}.niks3;
      defaultText = lib.literalExpression "inputs.niks3.packages.\${system}.niks3";
      description = "niks3 client used by the hook.";
    };

    serverUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://niks3.cafecito.cloud";
      description = "niks3 API server the post-build hook pushes to.";
    };

    tokenFile = lib.mkOption {
      type = lib.types.str;
      description = ''
        Path (at runtime, e.g. an agenix secret) to the niks3 API token.
        The hook runs as root inside the nix-daemon, so root-owned 0400 is
        fine.
      '';
    };

    pushTimeout = lib.mkOption {
      type = lib.types.int;
      default = 900;
      description = "Seconds before a single push invocation is killed (builds block on the hook).";
    };
  };

  config = lib.mkIf cfg.enable {
    nix.settings.post-build-hook = postBuildHook;
  };
}
