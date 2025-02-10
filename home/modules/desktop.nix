{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.chrisportela;
in
{
  options.chrisportela = {
    desktop = lib.mkEnableOption "Desktop related apps and settings";
  };

  config = lib.mkIf cfg.desktop {
    allowedUnfree = [
      "terraform"
      "vault-bin"
      "vscode"
      "discord"
      "obsidian"
    ];

    chrisportela.enableExtraPackages = lib.mkDefault true;

    programs = {
      vscode.enable = true;
      chromium.enable = true;
      mpv.enable = true;
    };

    services.ssh-agent.enable = true;

    home.packages = with pkgs; [
      beekeeper-studio
      discord
      jrnl
      obsidian
      ollama
      onlyoffice-bin_latest
      signal-desktop
      sqlitebrowser
      trayscale
      ansel
      darktable
    ];
  };
}
