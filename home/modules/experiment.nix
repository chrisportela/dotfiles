{ config, lib, ... }:
let
  cfg = config.chrisportela;
in
{
  options.chrisportela = {
    enableExtraPackages = lib.mkEnableOption "extra packages to play with";
  };

  config = lib.mkIf cfg.enableExtraPackages {
    programs = {
      # Tryouts
      # zed-editor.enable = true;
      pyenv.enable = false;
      poetry.enable = true;
      # ruff.enable = true; # need settings set
      zk.enable = true;
      vifm.enable = true;
      kitty.enable = true;
      rio.enable = true;
      neovide = {
        enable = true;
        settings = {
          # basic example settings
          fork = false;
          frame = "full";
          idle = true;
          maximized = false;
          neovim-bin = "/usr/bin/nvim";
          no-multigrid = false;
          srgb = false;
          tabs = true;
          theme = "auto";
          title-hidden = true;
          vsync = true;
          wsl = false;

          font = {
            normal = [ ];
            size = 14.0;
          };
        };
      };
      fastfetch.enable = true;
      bun.enable = true;
      ranger.enable = true;
      # arrpc.enable = false; # https://arrpc.openasar.dev/
      mise.enable = false; # https://mise.jdx.dev/about.html
      granted.enable = false; # https://github.com/common-fate/granted
      bacon.enable = false; # https://github.com/Canop/bacon background rust checker
      carapace = {
        # https://github.com/carapace-sh/carapace smart shell complete
        enable = false;
        # enableBashIntegration = false;
        # enableFishIntegration = false;
        # enableNushellIntegration = false;
        # enableZshIntegration = false;
      };
      yazi.enable = false; # https://github.com/sxyazi/yazi
      qcal.enable = false; # https://git.sr.ht/~psic4t/qcal
      # git-sync.enable = false; # https://github.com/simonthum/git-sync
      # https://github.com/pimalaya?view_as=public
      comodoro.enable = false;
      # See Also: services.comodoro.enable = false;
      git-credential-oauth.enable = false;
      # git-credential-manager.enable = false;
      # git-credential-keepassxc.enable = false;
      jujutsu.enable = false;
      rbenv.enable = false;
      yt-dlp.enable = false;
      # --- end
    };
  };
}
