{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.chrisportela.mcp-servers;

  # A server's `env` attr can hold either plain strings or `{ _secret = path; }`
  # markers. The declarative JSON below contains only plain string entries; secret
  # entries are resolved at activation time by reading the file from disk and
  # injecting it via jq --rawfile.
  isSecret = v: builtins.isAttrs v && v ? _secret;

  # Build the declarative (build-time) representation of one server entry.
  # Drops null fields and any env vars that come from secret files.
  buildServer =
    name: srv:
    let
      plainEnv = lib.filterAttrs (_: v: !isSecret v) srv.env;
      base = {
        type = srv.type;
        args = srv.args;
        env = plainEnv;
        _nixManaged = true;
      };
      withCommand = lib.optionalAttrs (srv.command != null) { command = srv.command; };
      withUrl = lib.optionalAttrs (srv.url != null) { url = srv.url; };
    in
    base // withCommand // withUrl;

  # Per-server attrset of secret env vars: { ENV_NAME = "/path/to/secret"; ... }
  secretEnvFor = srv: lib.mapAttrs (_: v: v._secret) (lib.filterAttrs (_: isSecret) srv.env);

  declarativeServers = lib.mapAttrs buildServer cfg.servers;

  declarativeJson = pkgs.writeText "mcp-servers.json" (builtins.toJSON declarativeServers);

  # Names of all nix-managed servers, as a JSON array (for stale-entry cleanup).
  managedNamesJson = pkgs.writeText "mcp-server-names.json" (
    builtins.toJSON (lib.attrNames cfg.servers)
  );

  # Build the per-server jq invocations that inject secret env values at
  # activation time. Each line reads one secret file via --rawfile and assigns
  # it onto the corresponding server's env block.
  secretInjections = lib.concatStringsSep "\n" (
    lib.flatten (
      lib.mapAttrsToList (
        serverName: srv:
        lib.mapAttrsToList (envName: secretPath: ''
          if [ ! -r ${lib.escapeShellArg secretPath} ]; then
            echo "mcp-servers: secret file not readable: "${lib.escapeShellArg secretPath} >&2
            exit 1
          fi
          if [ ! -s ${lib.escapeShellArg secretPath} ]; then
            echo "mcp-servers: secret file is empty: "${lib.escapeShellArg secretPath} >&2
            exit 1
          fi
          declarative=$(${pkgs.jq}/bin/jq \
            --rawfile secret ${lib.escapeShellArg secretPath} \
            --arg server ${lib.escapeShellArg serverName} \
            --arg key ${lib.escapeShellArg envName} \
            '.[$server].env[$key] = ($secret | sub("\n+$"; ""))' \
            <<<"$declarative")
        '') (secretEnvFor srv)
      ) cfg.servers
    )
  );

  activationScript = ''
    set -eu

    claude_config="$HOME/.claude.json"

    # 1. Load existing config (or start empty if missing/malformed)
    if [ -f "$claude_config" ] && ${pkgs.jq}/bin/jq -e . "$claude_config" >/dev/null 2>&1; then
      existing=$(cat "$claude_config")
    else
      existing='{}'
    fi

    # 2. Ensure top-level mcpServers key exists
    existing=$(${pkgs.jq}/bin/jq '.mcpServers //= {}' <<<"$existing")

    # 3. Load the declarative servers from the nix store
    declarative=$(cat ${declarativeJson})

    # 4. Inject secret env vars (read at activation time, never in nix store)
    ${secretInjections}

    # 5. Drop stale nix-managed entries (managed before, no longer declared)
    managed_names=$(cat ${managedNamesJson})
    existing=$(${pkgs.jq}/bin/jq \
      --argjson names "$managed_names" \
      '.mcpServers |= with_entries(
        select(
          (.value._nixManaged != true) or
          (.key as $k | $names | index($k))
        )
      )' <<<"$existing")

    # 6. Merge declarative entries on top (overwriting any existing managed entry)
    merged=$(${pkgs.jq}/bin/jq \
      --argjson declarative "$declarative" \
      '.mcpServers = (.mcpServers + $declarative)' <<<"$existing")

    # 7. Write back atomically with pretty formatting
    tmp=$(mktemp "''${claude_config}.XXXXXX")
    printf '%s\n' "$merged" | ${pkgs.jq}/bin/jq '.' >"$tmp"
    mv "$tmp" "$claude_config"
    chmod 600 "$claude_config"
  '';
in
{
  options.chrisportela.mcp-servers = {
    enable = lib.mkEnableOption "MCP server management for Claude Code";

    servers = lib.mkOption {
      default = { };
      description = "MCP servers to register with Claude Code at user scope.";
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            type = lib.mkOption {
              type = lib.types.enum [
                "stdio"
                "http"
                "sse"
              ];
              default = "stdio";
              description = "Transport type for the MCP server.";
            };

            command = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Command to run (stdio servers).";
            };

            args = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Arguments passed to the command.";
            };

            url = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "URL for http/sse servers.";
            };

            env = lib.mkOption {
              type = lib.types.attrsOf (
                lib.types.either lib.types.str (
                  lib.types.submodule {
                    options._secret = lib.mkOption {
                      type = lib.types.path;
                      description = "Path to a file containing the secret value. Read at activation time.";
                    };
                  }
                )
              );
              default = { };
              description = "Environment variables. Plain strings or { _secret = /path; } for secrets.";
            };
          };
        }
      );
    };
  };

  config = lib.mkIf (cfg.enable && cfg.servers != { }) {
    home.activation.mcp-servers = lib.hm.dag.entryAfter [ "writeBoundary" ] activationScript;
  };
}
