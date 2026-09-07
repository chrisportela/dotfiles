# Forgejo Actions runner (NixOS) with pluggable backends.
# Ported from the infra repo's cafecito.forgejoRunners module so
# dotfiles-managed hosts (e.g. flamme) can join the runner fleet.
# See README.md for purpose, options, and dependencies.
{
  config,
  lib,
  pkgs,
  utils,
  ...
}:
let
  cfg = config.chrisportela.forgejo-runner;

  settingsFormat = pkgs.formats.yaml { };

  instanceModule =
    { name, ... }:
    {
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable this runner instance";
        };

        name = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "Display name for this runner";
        };

        backend = lib.mkOption {
          type = lib.types.enum [
            "docker"
            "native"
          ];
          default = "docker";
          description = "Execution backend for this runner";
        };

        uuid = lib.mkOption {
          type = lib.types.str;
          description = ''
            UUID of the pre-created runner on the Forgejo server
            (`forgejo-cli actions register`, or Site administration →
            Actions → Runners → Create runner). Together with the token it
            authenticates the runner like a username/password — no
            registration exchange happens. Each instance needs its own
            UUID+token pair; two daemons must never share one identity.
          '';
        };

        tokenFile = lib.mkOption {
          type = lib.types.path;
          description = ''
            Path to file containing TOKEN=<value>, where <value> is the
            40-character hexadecimal secret paired with `uuid`. Loaded as a
            systemd EnvironmentFile and injected into the runner config at
            service start (the rendered store config only carries a
            placeholder).
          '';
        };

        labels = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          description = ''
            Runner labels (e.g., ["nix:host"] or
            ["x:docker://node:20-bookworm"]). Set in the daemon config
            (synced to the server on startup), so label changes do NOT
            re-register the runner.
          '';
          example = [ "ubuntu-latest:docker://node:20-bookworm" ];
        };

        timeout = lib.mkOption {
          type = lib.types.str;
          default = "3h";
          description = "Maximum wall-clock time a single job may run (runner.timeout in config.yaml)";
        };

        capacity = lib.mkOption {
          type = lib.types.int;
          default = 1;
          description = "Number of jobs this runner executes concurrently (runner.capacity in config.yaml)";
        };

        docker = {
          networkMode = lib.mkOption {
            type = lib.types.str;
            default = "bridge";
            description = "Docker network mode";
          };

          shareHostNixStore = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Bind-mount the host's /nix/store read-only and the nix-daemon
              socket read-write into every job container, and set
              NIX_REMOTE=daemon. Containers can read from the host store and
              build new paths through the host daemon — sharing substituters,
              trusted-keys, and the cache configuration of the host.
              Container root connects to the daemon as host root, so this
              grants effective host-store write privilege; only enable for
              runners that exclusively execute trusted workloads.

              PATH is NOT overridden: the container keeps its image's PATH
              (so `node`, `git`, etc. work as the image intends). Workflows
              that want to call `nix` should prepend it themselves (the
              shared setup-nix action does this).
            '';
          };

          shareHostCAs = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Bind-mount the host's aggregated CA bundle
              (/etc/ssl/certs/ca-certificates.crt) over the standard
              Debian/Ubuntu path inside the container, and set SSL_CERT_FILE
              and NODE_EXTRA_CA_CERTS so non-default tooling (Node, anything
              using OpenSSL's env override) finds it. Enable for runners that
              need to talk to TLS endpoints signed by the internal
              cafecitocloud root CA (e.g. git.cafecito.cloud).
            '';
          };

          extraHosts = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = ''
              Hostnames to map to Docker's host-gateway inside every job
              container (rendered as `--add-host=<name>:host-gateway`).
              Use for internal names the host resolves to 127.0.0.1 via a
              local redirect zone — without this, the container resolves
              them to its own loopback and the connection fails. The host
              service must listen on an interface reachable from the docker
              bridge (i.e. not bound exclusively to 127.0.0.1).
            '';
            example = [ "git.cafecito.cloud" ];
          };
        };

        native = {
          packages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
            description = "Extra packages available on the runner's PATH";
          };
        };
      };
    };

  enabledInstances = lib.filterAttrs (_: inst: inst.enable) cfg.instances;
in
{
  options.chrisportela.forgejo-runner = {
    enable = lib.mkEnableOption "Forgejo Actions runners";

    serverUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://git.cafecito.cloud";
      description = "Forgejo server URL that runners register with";
    };

    instances = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule instanceModule);
      default = { };
      description = "Runner instances to configure";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = lib.concatMap (
      name:
      lib.optional (cfg.instances.${name}.backend == "docker") {
        assertion = config.virtualisation.docker.enable || config.virtualisation.podman.enable;
        message = "Docker runner backend requires Docker or Podman to be enabled (instance: ${name})";
      }
    ) (builtins.attrNames enabledInstances);

    services.gitea-actions-runner = {
      package = pkgs.forgejo-runner;
      instances = lib.mapAttrs (
        _name: inst:
        let
          isDocker = inst.backend == "docker";
          nixShareOpts = lib.optionals (isDocker && inst.docker.shareHostNixStore) [
            "-v /nix/store:/nix/store:ro"
            "-v /nix/var/nix/daemon-socket:/nix/var/nix/daemon-socket"
            "-e NIX_REMOTE=daemon"
          ];
          nixShareVols = lib.optionals (isDocker && inst.docker.shareHostNixStore) [
            "/nix/store"
            "/nix/var/nix/daemon-socket"
          ];
          caShareOpts = lib.optionals (isDocker && inst.docker.shareHostCAs) [
            "-v /etc/ssl/certs/ca-certificates.crt:/etc/ssl/certs/ca-certificates.crt:ro"
            "-e SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt"
            "-e NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt"
          ];
          caShareVols = lib.optionals (isDocker && inst.docker.shareHostCAs) [
            "/etc/ssl/certs/ca-certificates.crt"
          ];
          extraHostOpts = lib.optionals isDocker (
            map (h: "--add-host=${h}:host-gateway") inst.docker.extraHosts
          );
          allContainerOpts = nixShareOpts ++ caShareOpts ++ extraHostOpts;
          allValidVolumes = nixShareVols ++ caShareVols;
        in
        {
          enable = true;
          name = inst.name;
          url = cfg.serverUrl;
          tokenFile = inst.tokenFile;
          labels = inst.labels;
          hostPackages = lib.mkIf (inst.backend == "native") (
            with pkgs;
            [
              bash
              coreutils
              curl
              gawk
              git
              gnused
              jq
              nix
              nodejs
            ]
            ++ inst.native.packages
          );
          settings = {
            # Labels live in the daemon config: forgejo-runner syncs config
            # labels to the server on startup, so label changes take effect
            # without touching the runner identity.
            runner = {
              labels = inst.labels;
              timeout = inst.timeout;
              capacity = inst.capacity;
            };
            # Declarative connection (Forgejo's current registration flow):
            # uuid+token authenticate directly, replacing `register`. The
            # token placeholder is substituted from $TOKEN at service start
            # — this file is world-readable in the nix store.
            server.connections.forgejo = {
              url = cfg.serverUrl;
              uuid = inst.uuid;
              token = "@FORGEJO_RUNNER_TOKEN@";
            };
          }
          // lib.optionalAttrs (allContainerOpts != [ ]) {
            container = {
              options = lib.concatStringsSep " " allContainerOpts;
              valid_volumes = allValidVolumes;
            };
          };
        }
      ) enabledInstances;
    };

    # Replace the upstream registration ExecStartPre entirely: with the
    # declarative uuid+token connection there is no registration step. The
    # store config carries a token placeholder (see settings above); the
    # real config is rendered into the instance state dir at start with the
    # secret substituted in, and ExecStart is pointed at that copy.
    systemd.services = lib.mapAttrs' (
      name: inst:
      lib.nameValuePair "gitea-runner-${utils.escapeSystemdPath name}" {
        serviceConfig =
          let
            configFile =
              settingsFormat.generate "config.yaml"
                config.services.gitea-actions-runner.instances.${name}.settings;
          in
          {
            ExecStartPre = lib.mkForce [
              (pkgs.writeShellScript "forgejo-runner-render-config-${name}" ''
                INSTANCE_DIR="$STATE_DIRECTORY/${name}"
                mkdir -vp "$INSTANCE_DIR"

                # Old registration-flow artifacts: a leftover .runner file
                # would shadow the declarative connection.
                rm -f "$INSTANCE_DIR/.runner" "$INSTANCE_DIR/.token-hash" "$INSTANCE_DIR/.labels"

                umask 077
                ${pkgs.gnused}/bin/sed \
                  "s|@FORGEJO_RUNNER_TOKEN@|$TOKEN|" \
                  ${configFile} > "$INSTANCE_DIR/config.yaml"
              '')
            ];
            ExecStart = lib.mkForce "${lib.getExe config.services.gitea-actions-runner.package} daemon --config \${STATE_DIRECTORY}/${name}/config.yaml";
          };
      }
    ) enabledInstances;
  };
}
