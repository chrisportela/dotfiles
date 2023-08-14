{ lib, pkgs, ... }: with lib; {
  imports = [ ];

  options = { base = { }; };

  config =
    let
      isDarwin = (builtins.hasAttr "launchd" options);
      isLinux = !isDarwin;
    in
    mkMerge [
      {
        # environment.pathsToLink = [ "/share/nix-direnv" ];
        environment.systemPackages = with pkgs; [
          nixpkgs-fmt
          curl
          git
        ];

        programs = {
          tmux.enable = true;
          zsh = {
            enable = true;
            enableBashCompletion = true;
            enableCompletion = true;
          };
        };
      }
      (mkIf isLinux {
        programs = optionalAttrs isLinux {
          neovim = {
            enable = mkDefault true;
            vimAlias = mkDefault true;
            viAlias = mkDefault true;
            defaultEditor = mkDefault true;
          };

          tmux = {
            enable = true;
            terminal = "screen-256color";
            clock24 = true;
            baseIndex = 1;
            newSession = true;
            plugins = with pkgs.tmuxPlugins; [ sensible ];
          };
        };
      })
      (mkIf isDarwin {
        programs = optionalAttrs isDarwin {
          zsh = {
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
      })
    ];
}
