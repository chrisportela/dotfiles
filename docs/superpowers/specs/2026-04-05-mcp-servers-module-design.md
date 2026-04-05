# MCP Servers Module & plane-mcp-server Package

**Date:** 2026-04-05
**Status:** Draft

## Overview

Two deliverables:
1. A Nix package for `plane-mcp-server` (Python, from PyPI)
2. A generic home-manager module (`chrisportela.mcp-servers`) that declaratively manages MCP server registrations for Claude Code

## Package: `pkgs/plane-mcp-server/`

### Approach

`buildPythonPackage` with `format = "pyproject"` for `plane-mcp-server` v0.2.8 and its missing dependencies.

### Dependencies to package

| Package | Version | Notes |
|---------|---------|-------|
| `plane-mcp-server` | 0.2.8 | Main package, setuptools build |
| `plane-sdk` | 0.2.8 | Plane Python SDK (depends on `requests`, `pydantic`) |
| `fastmcp` | 2.14.4 | FastMCP framework |
| `mcp` | 1.26.0 | Model Context Protocol library |
| `py-key-value-aio[redis]` | 0.3.0 | Async KV store with Redis extra |
| `PyJWT` | >=2.12.0 | JWT handling (likely in nixpkgs) |
| `authlib` | >=1.6.9 | OAuth library (likely in nixpkgs) |

Dependencies already in nixpkgs (`requests`, `pydantic`, `PyJWT`, `authlib`) are used directly.

### Structure

```
pkgs/plane-mcp-server/
├── default.nix          # Main derivation + inline dep packaging
```

### Wiring

- `flake.nix`: `plane-mcp-server = pkgs.pkgsUnstable.callPackage ./pkgs/plane-mcp-server/default.nix { };`
- `overlays/default.nix`: new overlay entry
- `lib/import-pkgs.nix`: add to overlay list

## Module: `modules/home/mcp-servers/`

### Options

```nix
options.chrisportela.mcp-servers = {
  enable = lib.mkEnableOption "MCP server management for Claude Code";

  servers = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        type = lib.mkOption {
          type = lib.types.enum [ "stdio" "http" "sse" ];
          default = "stdio";
        };
        command = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Command to run (stdio servers)";
        };
        args = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
        };
        url = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "URL (http/sse servers)";
        };
        env = lib.mkOption {
          type = lib.types.attrsOf (lib.types.either
            lib.types.str
            (lib.types.submodule {
              options._secret = lib.mkOption {
                type = lib.types.path;
                description = "Path to file containing the secret value";
              };
            })
          );
          default = {};
          description = "Environment variables. Use _secret for file-based secrets.";
        };
      };
    });
    default = {};
  };
};
```

### Activation script behavior

The module generates a home-manager activation script that:

1. Reads `~/.claude.json` (or starts with `{}` if missing)
2. Removes any servers with `"_nixManaged": true` that are no longer declared
3. For each declared server:
   - Resolves `_secret` env vars by reading the referenced file at activation time
   - Builds the server JSON with `_nixManaged: true` marker
4. Merges into the top-level `mcpServers` key (user scope)
5. Writes back to `~/.claude.json`

Uses `jq` for all JSON manipulation. If `~/.claude.json` is missing or contains invalid JSON, the script starts from `{}`. Secret file contents are read at activation time, not build time, so they never end up in the Nix store.

### Example usage

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

### Integration

- Imported in `modules/home/default.nix`
- `coding-agents.nix` sets `chrisportela.mcp-servers.enable = lib.mkDefault true;`
- Server definitions go in host-specific config (depend on secrets/instance URLs)

### Directory structure

```
modules/home/mcp-servers/
├── default.nix    # Module options + activation script
├── README.md      # Purpose, options, dependencies
```

## Secret management

A new agenix secret `secrets/plane-api-key.age` for the Plane API key. Referenced via `config.age.secrets.plane-api-key.path` in server env config.

The `_secret` pattern keeps secrets out of the Nix store — the activation script reads the file contents at runtime and injects them into `~/.claude.json`.

## Out of scope

- HTTP/SSE server types (option defined but not prioritized)
- OAuth configuration
- Project-scope `.mcp.json` management
- Claude Desktop (different app, different config)
