# Forgejo Actions runner as a nix-darwin launchd daemon (native backend).
# See README.md for purpose, options, and dependencies.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.chrisportela.forgejo-runner;

  settingsFormat = pkgs.formats.yaml { };

  configFile = settingsFormat.generate "forgejo-runner-config.yaml" {
    runner = {
      labels = cfg.labels;
      timeout = cfg.timeout;
      capacity = cfg.capacity;
    };
  };

  # Tools every job can rely on. actions/checkout and other JS actions need
  # node; nix itself must be the client for the host daemon.
  jobPath = lib.makeBinPath (
    with pkgs;
    [
      bash
      coreutils
      curl
      gawk
      git
      gnused
      gnutar
      gzip
      jq
      nix
      nodejs
    ]
    ++ cfg.extraPackages
  );

  # Registration is gated on a hash of the token: upstream forgejo-runner
  # re-registers whenever it is asked to, and every re-registration mints a
  # NEW runner identity server-side, orphaning the previous row in Forgejo's
  # runner list. Labels are synced from the daemon config file at startup,
  # so label changes never require re-registering. (Pattern ported from the
  # infra repo's NixOS forgejo-runner module.)
  runnerScript = pkgs.writeShellScript "forgejo-runner-daemon" ''
    set -euo pipefail
    cd ${lib.escapeShellArg cfg.stateDir}

    TOKEN="$(cat ${lib.escapeShellArg cfg.tokenFile})"
    TOKEN_HASH_CURRENT="$(printf '%s' "$TOKEN" | ${pkgs.coreutils}/bin/sha256sum | cut -d' ' -f1)"
    TOKEN_HASH_STORED="$(cat .token-hash 2>/dev/null || echo "")"

    if [ ! -e .runner ] || [ "$TOKEN_HASH_CURRENT" != "$TOKEN_HASH_STORED" ]; then
      rm -f .runner
      ${lib.getExe cfg.package} register --no-interactive \
        --instance ${lib.escapeShellArg cfg.serverUrl} \
        --token "$TOKEN" \
        --name ${lib.escapeShellArg cfg.name} \
        --labels ${lib.escapeShellArg (lib.concatStringsSep "," cfg.labels)} \
        --config ${configFile}
      printf '%s' "$TOKEN_HASH_CURRENT" > .token-hash
    fi

    exec ${lib.getExe cfg.package} daemon --config ${configFile}
  '';
in
{
  options.chrisportela.forgejo-runner = {
    enable = lib.mkEnableOption "Forgejo Actions runner (native launchd daemon)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.forgejo-runner;
      description = "forgejo-runner package to run.";
    };

    serverUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://git.cafecito.cloud";
      description = "Forgejo server URL the runner registers with (must be reachable, e.g. over tailscale).";
    };

    name = lib.mkOption {
      type = lib.types.str;
      description = "Display name for this runner in the Forgejo UI.";
    };

    labels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "darwin:host"
        "nix-darwin:host"
      ];
      description = "Runner labels. Synced from the daemon config on startup, so changes do not re-register.";
    };

    timeout = lib.mkOption {
      type = lib.types.str;
      default = "3h";
      description = "Maximum wall-clock time a single job may run (runner.timeout).";
    };

    capacity = lib.mkOption {
      type = lib.types.int;
      default = 1;
      description = "Number of jobs executed concurrently (runner.capacity).";
    };

    tokenFile = lib.mkOption {
      type = lib.types.str;
      description = ''
        Path (at runtime, e.g. an agenix secret) to a file containing the
        raw registration token. Must be readable by `user`.
      '';
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "cmp";
      description = "macOS user the runner daemon (and therefore every job) runs as.";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/forgejo-runner";
      description = "Directory for runner registration state, job workspaces, and logs.";
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Extra packages appended to the PATH jobs see.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Created as root at activation time; the daemon itself runs as cfg.user.
    system.activationScripts.extraActivation.text = lib.mkAfter ''
      mkdir -p ${lib.escapeShellArg cfg.stateDir}/logs
      chown ${lib.escapeShellArg cfg.user} ${lib.escapeShellArg cfg.stateDir} ${lib.escapeShellArg cfg.stateDir}/logs
    '';

    launchd.daemons.forgejo-runner = {
      command = runnerScript;
      serviceConfig = {
        Label = "cloud.cafecito.forgejo-runner";
        UserName = cfg.user;
        WorkingDirectory = cfg.stateDir;
        KeepAlive = true;
        RunAtLoad = true;
        ThrottleInterval = 30;
        StandardOutPath = "${cfg.stateDir}/logs/runner.log";
        StandardErrorPath = "${cfg.stateDir}/logs/runner.err.log";
        EnvironmentVariables = {
          # System paths last: xcrun/codesign and friends for anything a job
          # shells out to outside of nix builds.
          PATH = "${jobPath}:/usr/bin:/bin:/usr/sbin:/sbin";
          HOME = cfg.stateDir;
        };
      };
    };
  };
}
