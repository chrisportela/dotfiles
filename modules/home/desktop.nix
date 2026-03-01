{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.chrisportela.desktop;
in
{
  options.chrisportela.desktop = {
    enable = lib.mkEnableOption "Desktop related apps and settings";
  };

  config = lib.mkIf cfg.enable {
    allowedUnfree = [
      "terraform"
      "vault-bin"
      "vscode"
      "discord"
      "obsidian"
    ];

    chrisportela.experiment.enable = lib.mkDefault true;

    programs = {
      vscode.enable = true;
      chromium.enable = true;
      mpv.enable = true;
    };

    services.ssh-agent.enable = true;

    home.packages = with pkgs; [
      coder
      vault-bin
      #beekeeper-studio
      discord
      #jrnl
      obsidian
      ollama
      onlyoffice-desktopeditors
      #signal-desktop
      sqlitebrowser
      trayscale
      #ansel
      darktable
    ];
  };
}
