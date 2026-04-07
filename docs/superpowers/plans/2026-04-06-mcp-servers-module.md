# MCP Servers Module & plane-mcp-server Package Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Package `plane-mcp-server` for Nix and create a generic home-manager module that declaratively manages MCP server registrations in Claude Code's `~/.claude.json`.

**Architecture:** Two independent deliverables wired together. A `buildPythonPackage` derivation for `plane-mcp-server` (plus `plane-sdk` dep). A home-manager module with `chrisportela.mcp-servers` options that generates a `jq`-based activation script to merge server configs into `~/.claude.json` at user scope, with `_nixManaged` markers for idempotent updates and `_secret` file references for safe secret injection.

**Tech Stack:** Nix (flakes, home-manager, buildPythonPackage), jq, agenix

---

### Task 1: Package `plane-sdk`

The only missing nixpkgs dependency. A simple setuptools Python package.

**Files:**
- Create: `pkgs/plane-mcp-server/default.nix` (will contain both `plane-sdk` and `plane-mcp-server`)

- [ ] **Step 1: Create the package directory**

```bash
mkdir -p pkgs/plane-mcp-server
```

- [ ] **Step 2: Fetch the plane-sdk source hash**

```bash
nix-prefetch-url --unpack https://files.pythonhosted.org/packages/source/p/plane-sdk/plane_sdk-0.2.8.tar.gz
```

Record the hash. Convert to SRI format:

```bash
nix hash convert --hash-algo sha256 <hash>
```

- [ ] **Step 3: Write the package file with plane-sdk defined inline**

Create `pkgs/plane-mcp-server/default.nix`:

```nix
{
  lib,
  python3Packages,
  fetchPypi,
}:

let
  plane-sdk = python3Packages.buildPythonPackage rec {
    pname = "plane-sdk";
    version = "0.2.8";
    pyproject = true;

    src = fetchPypi {
      pname = "plane_sdk";
      inherit version;
      hash = "sha256-REPLACE_WITH_ACTUAL_HASH";
    };

    build-system = with python3Packages; [
      setuptools
      wheel
    ];

    dependencies = with python3Packages; [
      requests
      pydantic
    ];

    pythonImportsCheck = [ "plane_sdk" ];

    meta = {
      description = "Python SDK for Plane project management";
      homepage = "https://github.com/makeplane/plane-sdk-python";
      license = lib.licenses.mit;
    };
  };
in
python3Packages.buildPythonPackage rec {
  pname = "plane-mcp-server";
  version = "0.2.8";
  pyproject = true;

  src = fetchPypi {
    pname = "plane_mcp_server";
    inherit version;
    hash = "sha256-REPLACE_WITH_ACTUAL_HASH";
  };

  build-system = with python3Packages; [
    setuptools
    wheel
  ];

  dependencies = with python3Packages; [
    fastmcp
    plane-sdk
    py-key-value-aio
    mcp
    pyjwt
    authlib
  ];

  pythonRelaxDeps = [
    "fastmcp"
    "mcp"
    "py-key-value-aio"
  ];

  pythonImportsCheck = [ "plane_mcp" ];

  meta = {
    description = "Model Context Protocol server for Plane integration";
    homepage = "https://github.com/makeplane/plane-mcp-server";
    license = lib.licenses.mit;
    mainProgram = "plane-mcp-server";
  };
}
```

- [ ] **Step 4: Fetch the plane-mcp-server source hash**

```bash
nix-prefetch-url --unpack https://files.pythonhosted.org/packages/source/p/plane-mcp-server/plane_mcp_server-0.2.8.tar.gz
```

Convert to SRI and update the hash in the file.

- [ ] **Step 5: Test the build**

```bash
git add pkgs/plane-mcp-server/
nix build .#plane-mcp-server
```

Fix any build errors. Verify the binary exists:

```bash
ls result/bin/plane-mcp-server
```

- [ ] **Step 6: Commit**

```bash
git add pkgs/plane-mcp-server/
git commit -m "pkgs: add plane-mcp-server package"
```

---

### Task 2: Wire plane-mcp-server into flake.nix and overlays

**Files:**
- Modify: `flake.nix` (packages section, ~line 139-161)
- Modify: `overlays/default.nix`
- Modify: `lib/import-pkgs.nix`

- [ ] **Step 1: Add to flake.nix packages**

In `flake.nix`, inside the first attrset of the `packages` fold (after the `claude-code` line ~148), add:

```nix
plane-mcp-server = pkgs.pkgsUnstable.callPackage ./pkgs/plane-mcp-server/default.nix { };
```

- [ ] **Step 2: Add overlay in overlays/default.nix**

Add after the `peekaboo` overlay (~line 63):

```nix
plane-mcp-server = (
  final: prev: {
    plane-mcp-server = self.packages.${final.stdenv.system}.plane-mcp-server;
  }
);
```

- [ ] **Step 3: Register overlay in lib/import-pkgs.nix**

Add `plane-mcp-server` to the overlay list (~line 27, after `peekaboo`):

```nix
++ (with (import ../overlays/default.nix { inherit self inputs; }); [
    rust
    rustToolchain
    deploy-rs
    terraform
    setup-envrc
    claude-code
    openclaw
    opencode-cursor
    cliclick
    peekaboo
    plane-mcp-server
  ]);
```

- [ ] **Step 4: Verify the build still works**

```bash
nix build .#plane-mcp-server
result/bin/plane-mcp-server --help
```

- [ ] **Step 5: Commit**

```bash
git add flake.nix overlays/default.nix lib/import-pkgs.nix
git commit -m "wire plane-mcp-server into flake packages and overlays"
```

---

### Task 3: Create the MCP servers home-manager module

**Files:**
- Create: `modules/home/mcp-servers/default.nix`
- Create: `modules/home/mcp-servers/README.md`

- [ ] **Step 1: Create the module directory**

```bash
mkdir -p modules/home/mcp-servers
```

- [ ] **Step 2: Write the module**

Create `modules/home/mcp-servers/default.nix`:

```nix
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.chrisportela.mcp-servers;

  # Build the JSON for a single server entry
  serverToJson = name: server:
    let
      baseAttrs = {
        _nixManaged = true;
      } // lib.optionalAttrs (server.type == "stdio") {
        type = "stdio";
        command = server.command;
        args = server.args;
      } // lib.optionalAttrs (server.type == "http" || server.type == "sse") {
        type = server.type;
        url = server.url;
      };
    in
    baseAttrs;

  # Build env resolution script for a single server
  # Plain strings are passed through; { _secret = path; } reads the file at activation time
  envScript = name: server:
    let
      envEntries = lib.mapAttrsToList (
        envName: envValue:
        if builtins.isString envValue then
          ''jq_env_args+=(--arg "${envName}" "${envValue}")''
        else
          ''jq_env_args+=(--arg "${envName}" "$(cat ${lib.escapeShellArg envValue._secret})")''
      ) server.env;
    in
    lib.concatStringsSep "\n" envEntries;

  # Generate the full activation script
  activationScript =
    let
      serverNames = builtins.attrNames cfg.servers;
      managedNamesJson = builtins.toJSON serverNames;

      serverScripts = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (
          name: server:
          let
            baseJson = builtins.toJSON (serverToJson name server);
          in
          ''
            # Server: ${name}
            jq_env_args=()
            ${envScript name server}

            env_obj='{}'
            if [ ''${#jq_env_args[@]} -gt 0 ]; then
              env_pairs=""
              ${lib.concatStringsSep "\n" (
                lib.mapAttrsToList (
                  envName: envValue:
                  if builtins.isString envValue then
                    ''env_pairs+="\"${envName}\": \"${envValue}\","''
                  else
                    ''
                      secret_val="$(cat ${lib.escapeShellArg envValue._secret} | tr -d '\n')"
                      env_pairs+="\"${envName}\": $(${pkgs.jq}/bin/jq -Rs '.' <<< "$secret_val"),"
                    ''
                ) server.env
              )}
              env_pairs="''${env_pairs%,}"
              env_obj="{$env_pairs}"
            fi

            server_json='${baseJson}'
            server_json=$(echo "$server_json" | ${pkgs.jq}/bin/jq --argjson env "$env_obj" '. + {env: $env}')

            claude_json=$(echo "$claude_json" | ${pkgs.jq}/bin/jq --argjson server "$server_json" '.mcpServers["${name}"] = $server')
          ''
        ) cfg.servers
      );
    in
    ''
      CLAUDE_JSON="$HOME/.claude.json"

      # Read existing file or start fresh
      if [ -f "$CLAUDE_JSON" ] && ${pkgs.jq}/bin/jq empty "$CLAUDE_JSON" 2>/dev/null; then
        claude_json=$(cat "$CLAUDE_JSON")
      else
        claude_json='{}'
      fi

      # Ensure mcpServers key exists
      claude_json=$(echo "$claude_json" | ${pkgs.jq}/bin/jq '. + {mcpServers: (.mcpServers // {})}')

      # Remove previously nix-managed servers that are no longer declared
      managed_names='${managedNamesJson}'
      claude_json=$(echo "$claude_json" | ${pkgs.jq}/bin/jq --argjson managed "$managed_names" '
        .mcpServers |= with_entries(
          select(
            (.value._nixManaged != true) or
            (.key as $k | $managed | index($k) != null)
          )
        )
      ')

      ${serverScripts}

      # Write back
      echo "$claude_json" | ${pkgs.jq}/bin/jq '.' > "$CLAUDE_JSON"
    '';
in
{
  options.chrisportela.mcp-servers = {
    enable = lib.mkEnableOption "MCP server management for Claude Code";

    servers = lib.mkOption {
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
      default = { };
      description = "MCP servers to register with Claude Code at user scope.";
    };
  };

  config = lib.mkIf (cfg.enable && cfg.servers != { }) {
    home.activation.mcp-servers = lib.hm.dag.entryAfter [ "writeBoundary" ] activationScript;
  };
}
```

- [ ] **Step 3: Write the README**

Create `modules/home/mcp-servers/README.md`:

```markdown
# MCP Servers Module

Declaratively manage MCP server registrations for Claude Code. Merges server
configs into `~/.claude.json` at user scope using a `jq`-based activation
script. Nix-managed servers are tracked with a `_nixManaged` marker for
idempotent updates.

## Options

All options under `chrisportela.mcp-servers`:

- `enable` — Enable MCP server management
- `servers.<name>.type` — Transport: `stdio`, `http`, or `sse` (default: `stdio`)
- `servers.<name>.command` — Command to run (stdio servers)
- `servers.<name>.args` — Arguments passed to the command
- `servers.<name>.url` — URL (http/sse servers)
- `servers.<name>.env` — Environment variables; plain strings or `{ _secret = path; }` for secrets

## Dependencies

- `jq` — Used by the activation script (pulled automatically)
- agenix (optional) — For secret file references

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
```

- [ ] **Step 4: Commit**

```bash
git add modules/home/mcp-servers/
git commit -m "modules/home: add mcp-servers module for Claude Code"
```

---

### Task 4: Wire the module into home-manager and coding-agents

**Files:**
- Modify: `modules/home/default.nix` (imports list, ~line 8-16)
- Modify: `modules/home/coding-agents.nix` (~line 16)

- [ ] **Step 1: Add import in default.nix**

In `modules/home/default.nix`, add `./mcp-servers` to the imports list:

```nix
imports = [
  ./nixpkgs.nix
  ./difftastic.nix
  ./experiment.nix
  ./coding-agents.nix
  ./desktop.nix
  ./shell
  ./tmux
  ./mcp-servers
];
```

- [ ] **Step 2: Enable in coding-agents.nix**

In `modules/home/coding-agents.nix`, inside the `config = lib.mkIf cfg.enable {` block, add:

```nix
chrisportela.mcp-servers.enable = lib.mkDefault true;
```

- [ ] **Step 3: Test the full config builds**

```bash
nix build .
```

This builds the default home-manager config. It should succeed with `mcp-servers` enabled (via `coding-agents`) but no servers defined (which is a no-op — the activation script only runs when `servers != {}`).

- [ ] **Step 4: Commit**

```bash
git add modules/home/default.nix modules/home/coding-agents.nix
git commit -m "wire mcp-servers module into home-manager and coding-agents"
```

---

### Task 5: Add plane-mcp-server to a host config

This task adds the actual plane server definition. The secret needs to exist or be created.

**Files:**
- Modify: host config that enables `coding-agents` (e.g., the `cmp@ada` config in `flake.nix` or a host-specific module)

- [ ] **Step 1: Determine where the plane server config goes**

Check which host configs enable `coding-agents` and have agenix secrets available. Look at:

```bash
grep -r "coding-agents" modules/ hosts/ flake.nix
grep -r "age.secrets" modules/ hosts/ flake.nix
```

The plane server definition should go in the host-specific config for the machine(s) that need it.

- [ ] **Step 2: Add the plane server definition**

In the appropriate host config, add:

```nix
chrisportela.mcp-servers.servers.plane = {
  type = "stdio";
  command = "${pkgs.plane-mcp-server}/bin/plane-mcp-server";
  args = [ "stdio" ];
  env = {
    PLANE_WORKSPACE_SLUG = "cafecitocloud";
    PLANE_INSTANCE_URL = "https://plane.cafecito.cloud";
    PLANE_API_KEY._secret = config.age.secrets.plane-api-key.path;
  };
};
```

If the agenix secret doesn't exist yet, create it:

```bash
cd secrets/
agenix -e plane-api-key.age
```

And add it to `secrets/secrets.nix`.

- [ ] **Step 3: Test the build**

```bash
nix build .
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "hosts: add plane MCP server for Claude Code"
```

---

### Task 6: End-to-end verification

- [ ] **Step 1: Apply the config**

```bash
nix run . -- -b backup switch
```

- [ ] **Step 2: Verify ~/.claude.json has the server**

```bash
jq '.mcpServers.plane' ~/.claude.json
```

Expected: a JSON object with `type`, `command`, `args`, `env` (with resolved secret), and `_nixManaged: true`.

- [ ] **Step 3: Verify the binary works**

```bash
plane-mcp-server --help
```

- [ ] **Step 4: Test in Claude Code**

Start a Claude Code session and verify MCP tools from plane are available:

```
/mcp
```

Expected: plane server shows as connected.

- [ ] **Step 5: Test idempotency**

Run activation again and verify `~/.claude.json` is unchanged:

```bash
cp ~/.claude.json /tmp/before.json
nix run . -- -b backup switch
diff /tmp/before.json ~/.claude.json
```

Expected: no diff (or only formatting differences).
