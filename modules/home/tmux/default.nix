{ pkgs, lib, ... }:
{
  programs.tmux = {
    enable = true;
    shortcut = "a";
    keyMode = "vi";
    baseIndex = 1;
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

      set -g monitor-bell on;
      set -g window-status-bell-style 'fg=red,bold'

      bind C-a send-keys C-b;
      bind a send-keys C-b;
      bind s choose-tree -sF '#{?window_id,#{?window_bell_flag,#[fg=red bold],}#{window_index}: #{window_name}#{window_flags},#{?session_alerts,#[fg=red bold](!), }(#{session_windows} windows)}';
    '';
    # plugins = with pkgs.tmuxPlugins; [ ];
  };
}
