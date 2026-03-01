{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.chrisportela.darwin-common;
in
{
  options.chrisportela.darwin-common = {
    enable = lib.mkEnableOption "Darwin common (zsh, tmux, vim, system packages)";
  };

  config = lib.mkIf cfg.enable {
    environment.pathsToLink = [ "/share/nix-direnv" ];
    environment.systemPackages = with pkgs; [
      nixfmt-rfc-style
      curl
      git
      ntfy-sh
    ];

    programs = {
      zsh = {
        enable = true;
        enableBashCompletion = true;
        enableCompletion = true;
        enableFzfCompletion = true;
        enableFzfGit = true;
        enableFzfHistory = true;
      };

      vim = {
        enable = mkDefault true;
        enableSensible = mkDefault true; # Warning: uses 'VAM'
      };

      tmux = {
        enable = true;
        enableMouse = mkDefault true;
        enableSensible = mkDefault true;
      };
    };
  };
}
