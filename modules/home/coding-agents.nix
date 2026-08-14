{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.chrisportela.coding-agents;
in
{

  options.chrisportela.coding-agents = {
    enable = lib.mkEnableOption "coding agents";
    localLlm.enable = lib.mkEnableOption "aichat client + config pointing at https://vllm.ada.i.cafecito.cloud (the local vLLM service, reachable to tailnet members)";
  };

  config = lib.mkIf cfg.enable {
    allowedUnfree = [
      "cursor"
      "cursor-agent"
      "cursor-cli"
      "codex"
      "claude-code"
    ];
    # TODO: Make this module optional

    programs.claude-code = {
      enable = true;
      skills = {
        # Upstream ships the skill without YAML frontmatter, which Claude
        # Code needs for discovery — prepend it and inline the rest.
        claude-history = ''
          ---
          name: claude-history
          description: Search and read past Claude Code conversations with the claude-history CLI. Use when the user references a previous session or past conversation, asks what was decided or done before, or wants to find, quote, or resume prior work.
          ---

        ''
        + builtins.readFile "${pkgs.claude-history.src}/skills/claude-history/SKILL.md";
        # Repo path, not "${pkgs.claude-session}/share/...": home-manager's
        # mkSkillEntry stats the path at eval time, which would force building
        # the package during evaluation (IFD) and break `nix flake check`.
        session = ../../pkgs/claude-session/skill;
      };
    };

    chrisportela.mcp-servers.enable = lib.mkDefault true;

    home.packages =
      with pkgs;
      [
        codex
        context7
        opencode
        opencode-cursor
        claude-code
        claude-history
        claude-monitor
        claude-session
      ]
      ++ [
        cursor-agent
      ]
      ++ lib.optionals pkgs.stdenv.isLinux [
        code-cursor-fhs
      ]
      ++ lib.optionals cfg.localLlm.enable [
        aichat
        (pkgs.symlinkJoin {
          name = "pi-coding-agent";
          buildInputs = [ pkgs.makeWrapper ];
          paths = [ pkgs.pi-coding-agent ];
          postBuild = ''
            wrapProgram $out/bin/pi \
              --set NPM_CONFIG_PREFIX ${config.home.homeDirectory}/.pi/npm/ \
              --prefix PATH : ${
                pkgs.lib.makeBinPath [
                  pkgs.nodejs_latest
                ]
              }
          '';
        })
      ];

    chrisportela.mcp-servers.servers.context7 = {
      type = "stdio";
      command = "${pkgs.context7}/bin/context7-mcp";
    };

    # OpenCode Cursor plugin: symlink so OpenCode loads it from ~/.config/opencode/plugin/.
    # Add "cursor-acp" to the plugin array in ~/.config/opencode/opencode.json and the
    # cursor-acp provider block (see https://github.com/Nomadcxx/opencode-cursor). Then run
    # opencode-cursor-sync-models (requires cursor-agent and python3 on PATH) to sync models.
    xdg.configFile = {
      "opencode/plugin/cursor-acp.js".source =
        "${pkgs.opencode-cursor}/share/opencode-cursor/plugin-entry.js";
    }
    // lib.optionalAttrs cfg.localLlm.enable {
      "aichat/config.yaml".text = ''
        model: ada:ada
        clients:
          - type: openai-compatible
            name: ada
            api_base: https://vllm.ada.i.cafecito.cloud/v1
            api_key: dummy
            models:
              - name: ada
      '';
    };

  };
}
