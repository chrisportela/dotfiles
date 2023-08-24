{ lib, pkgs, ... }: with lib; {
  imports = [ ];

  config = {
    environment.pathsToLink = [ "/share/nix-direnv" ];
    environment.systemPackages = with pkgs; [
      nixpkgs-fmt
      curl
      git
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
        enableSensible = mkDefault true;
      };

      tmux = {
        enable = true;
        enableMouse = mkDefault true;
        enableSensible = mkDefault true;
      };
    };
  };
}
