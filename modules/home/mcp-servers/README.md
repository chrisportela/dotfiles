# MCP Servers Module

Declaratively manages MCP (Model Context Protocol) server registrations for
Claude Code by merging entries into the user-scope `mcpServers` key of
`~/.claude.json` from a home-manager activation script. Nix-managed entries are
tagged with `_nixManaged: true` so they can be updated or removed idempotently
without disturbing servers added manually via `claude mcp add`.

## Options

All options under `chrisportela.mcp-servers`:

- `enable` — Enable MCP server management for Claude Code
- `servers.<name>` — Server definitions (see Server Options below)

### Server Options

- `type` — Transport type. One of: `stdio` (default), `http`, `sse`
- `command` — Command to run for `stdio` servers
- `args` — List of arguments passed to the command (default: `[]`)
- `url` — URL for `http` / `sse` servers
- `env` — Environment variables. Each value is either a plain string or
  `{ _secret = /path/to/file; }` to read the value from a file at activation
  time (suitable for agenix-decrypted secrets)

## Dependencies

- `jq` — Used by the activation script to manipulate `~/.claude.json`
- Agenix — Optional, only needed if any server uses `_secret` env vars

## Example

```nix
chrisportela.mcp-servers = {
  enable = true;

  servers.plane = {
    type = "stdio";
    command = "${pkgs.plane-mcp-server}/bin/plane-mcp-server";
    args = [ "stdio" ];
    env = {
      PLANE_WORKSPACE_SLUG = "cafecitocloud";
      PLANE_API_KEY._secret = config.age.secrets.plane-api-key.path;
    };
  };
};
```

## Notes

- Secret file contents are read at activation time and never embedded in the
  Nix store. A trailing newline (common in agenix-decrypted files) is stripped
  before injection.
- Existing entries in `mcpServers` that are not `_nixManaged` are preserved, so
  servers added with `claude mcp add` continue to work alongside declared ones.
- Removing a server from the Nix configuration drops it from `~/.claude.json`
  on the next home-manager activation.
- The activation script falls back to an empty config if `~/.claude.json` is
  missing or malformed, so first-time bootstraps work cleanly.
