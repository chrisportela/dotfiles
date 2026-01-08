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
      cursor-cli
      code-cursor-fhs
      claude-code
      claude-monitor
    ];

  };
}
