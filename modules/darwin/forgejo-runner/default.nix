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

  # Declarative pre-registered runner (forgejo-runner v12+): the connection
  # is defined entirely in the config file — url + uuid + token loaded from
  # a file — replacing the deprecated `register`/`create-runner-file`
  # commands. The runner identity is created server-side once with
  # `forgejo-cli actions register --secret <secret>`, which mints and
  # prints the uuid; nothing is created at runtime and there is no
  # orphaned-runner problem.
  configFile = settingsFormat.generate "forgejo-runner-config.yaml" {
    runner = {
      labels = cfg.labels;
      timeout = cfg.timeout;
      capacity = cfg.capacity;
    };
    server.connections.cafecito = {
      url = cfg.serverUrl;
      uuid = cfg.uuid;
      token_url = "file:${cfg.secretFile}";
    };
  };

  # Nix-built tools (git/curl/node/nix) use OpenSSL and never consult the
  # macOS Keychain, so trusting an internal CA in the Keychain does nothing
  # for them — they need a PEM bundle via environment variables. Bundle the
  # standard Mozilla roots with any extra CAs (darwin analog of the infra
  # runners' shareHostCAs).
  caBundle = pkgs.runCommand "forgejo-runner-ca-bundle" { } ''
    cat ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \
      ${lib.concatMapStringsSep " " lib.escapeShellArg cfg.extraCertificateFiles} \
      > $out
  '';

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

  runnerScript = pkgs.writeShellScript "forgejo-runner-daemon" ''
    set -euo pipefail
    cd ${lib.escapeShellArg cfg.stateDir}
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

    uuid = lib.mkOption {
      type = lib.types.str;
      description = ''
        UUID of the pre-registered runner; printed by
        `forgejo-cli actions register`. Not sensitive — the secret is.
      '';
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

    secretFile = lib.mkOption {
      type = lib.types.str;
      description = ''
        Path (at runtime, e.g. an agenix secret) to a file containing the
        raw 40-hex-char shared secret (`openssl rand -hex 20`) this runner
        was pre-registered with on the server
        (`forgejo-cli actions register --secret <secret>`). Must be
        readable by `user`.
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

    extraCertificateFiles = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = ''
        PEM certificate files appended to the CA bundle the daemon and its
        jobs use (SSL_CERT_FILE etc.). Needed for TLS endpoints signed by
        an internal CA (e.g. the Cafecito Cloud Root CA for
        git.cafecito.cloud) — nix-built git/curl/node do not read the
        macOS Keychain.
      '';
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
          # OpenSSL-based tools (git via curl), the nix client, and node all
          # take their trust roots from these — see caBundle above.
          SSL_CERT_FILE = "${caBundle}";
          NIX_SSL_CERT_FILE = "${caBundle}";
          GIT_SSL_CAINFO = "${caBundle}";
          NODE_EXTRA_CA_CERTS = "${caBundle}";
        };
      };
    };
  };
}
