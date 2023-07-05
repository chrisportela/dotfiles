{ lib, config, ... }: {

  programs.starship = {
    enable = lib.mkDefault true;
    enableZshIntegration = true;
    settings =
      let
        username = config.home.username;
      in
      {
        add_newline = false;
        format = lib.concatStrings [
          "$env_var"
          "$hostname"
          "$directory"
          "$git_branch"
          "$git_commit"
          "$git_state"
          "$git_metrics"
          "$git_status"
          "$hg_branch"
          "$kubernetes"
          "$docker_context"
          "$package"
          "$c"
          "$cmake"
          "$helm"
          "$terraform"
          "$nix_shell"
          "$memory_usage"
          "$gcloud"
          "$custom"
          "$sudo"
          "$cmd_duration"
          "$line_break"
          "$jobs"
          "$time"
          "$status"
          "$shell"
          "$character"
        ];
        cmd_duration = {
          min_time = 10000;
          format = " took [$duration]($style)";
        };
        directory = {
          truncation_length = 5;
          format = "in [$path]($style)[$lock_symbol]($lock_style) ";
        };
        kubernetes = {
          disabled = false;
        };
        package.disabled = true;
        gcloud = {
          disabled = true;
          format = "on [$symbol$account(@$domain)(\($region\))]($style) ";
        };
        hostname = {
          ssh_only = false;
          ssh_symbol = "🌐 ";
          format = "on [$ssh_symbol$hostname]($style) ";
          style = "dimmed italic green";
        };
        env_var = {
          username = {
            format = "[$env_value]($style) ";
            style = "dimmed purple";
          };
          workspace = {
            variable = "CODER_WORKSPACE_NAME";
            format = "on [$env_value]($style) ";
            style = "dimmed italic green";
          };
        };
      };
  };
}
