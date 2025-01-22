{ pkgs, lib, ... }:
{
  programs.tmux = {
    enable = true;
    shortcut = "a";
    keyMode = "vi";
    baseIndex = 0;
    clock24 = true;
    newSession = true;
    secureSocket = false;
    prefix = "C-a";
    # terminal = "xterm-256color";
    terminal = "screen-256color";
    escapeTime = 50;
    historyLimit = 30000;
    extraConfig = ''
      set-option -g allow-passthrough on;
    '';
    # plugins = with pkgs.tmuxPlugins; [ ];
  };
}
