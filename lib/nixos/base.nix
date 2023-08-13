{ lib, pkgs, ... }: with lib; {
  imports = [ ];

  options = { base = { }; };

  config = {
    # environment.pathsToLink = [ "/share/nix-direnv" ];
    environment.systemPackages = with pkgs; [
      nixpkgs-fmt
      curl
      git
    ];

    programs = {


      zsh = {
        enable = mkDefault true;
        enableBashCompletion = mkDefault true;
        enableCompletion = mkDefault true;
      } // optionalAttrs pkgs.stdenv.isDarwin {
        enableFzfCompletion = mkDefault true;
        enableFzfGit = mkDefault true;
        enableFzfHistory = mkDefault true;
      };

      tmux = {
        enable = mkDefault true;
      } // optionalAttrs pkgs.stdenv.isLinux {
        terminal = "screen-256color";
        clock24 = true;
        baseIndex = 1;
        newSession = true;
        plugins = with pkgs.tmuxPlugins; [ sensible ];
      } // optionalAttrs pkgs.stdenv.isDarwin {
        enableMouse = mkDefault true;
        enableSensible = mkDefault true;
      };
    } // (if pkgs.stdenv.isDarwin then {
      vim = mkIf pkgs.stdenv.isDarwin {
        enable = mkDefault true;
        enableSensible = mkDefault true;
      };
    } else {
      neovim = {
        enable = mkDefault true;
        vimAlias = mkDefault true;
        viAlias = mkDefault true;
        defaultEditor = mkDefault true;
      };
    });
  };
}
