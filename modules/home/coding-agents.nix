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
  };

  config = lib.mkIf cfg.enable {
    allowedUnfree = [
      "cursor"
      "cursor-cli"
      "codex"
      "claude-code"
    ];
    # TODO: Make this module optional

    programs.claude-code = {
      enable = true;
    };

    home.packages = with pkgs; [
      codex
      opencode
      opencode-cursor
      cursor-cli
      code-cursor-fhs
      claude-code
      claude-monitor
    ];

    # OpenCode Cursor plugin: symlink so OpenCode loads it from ~/.config/opencode/plugin/.
    # Add "cursor-acp" to the plugin array in ~/.config/opencode/opencode.json and the
    # cursor-acp provider block (see https://github.com/Nomadcxx/opencode-cursor). Then run
    # opencode-cursor-sync-models (requires cursor-agent and python3 on PATH) to sync models.
    xdg.configFile."opencode/plugin/cursor-acp.js".source =
      "${pkgs.opencode-cursor}/share/opencode-cursor/plugin-entry.js";

  };
}
