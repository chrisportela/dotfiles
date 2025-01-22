{ lib, pkgs, ... }:
with lib;
{
  imports = [ ];

  config = {
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
