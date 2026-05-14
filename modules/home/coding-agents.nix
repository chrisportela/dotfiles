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
    localLlm.enable = lib.mkEnableOption "aichat config pointing at a local vLLM at 127.0.0.1:8000 (set on hosts that run the local-llm module)";
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
    };

    chrisportela.mcp-servers.enable = lib.mkDefault true;

    home.packages =
      with pkgs;
      [
        aichat
        codex
        context7
        opencode
        opencode-cursor
        claude-code
        claude-monitor
      ]
      ++ [
        cursor-agent
      ]
      ++ lib.optionals pkgs.stdenv.isLinux [
        code-cursor-fhs
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
    # aichat default config: only on hosts running a local vLLM. Targets
    # 127.0.0.1:8000 since the public vhost (vllm.ada.i.cafecito.cloud)
    # needs DNS + ACME before it's reachable.
    // lib.optionalAttrs cfg.localLlm.enable {
      "aichat/config.yaml".text = ''
        model: ada:ada
        clients:
          - type: openai-compatible
            name: ada
            api_base: http://127.0.0.1:8000/v1
            api_key: dummy
            models:
              - name: ada
      '';
    };

  };
}
