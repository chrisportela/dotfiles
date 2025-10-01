{
  lib,
  config,
  pkgs,
  ...
}:
{
  imports = [
    ../common.nix
    ../nixpkgs.nix
    ../stats.nix
  ];

  environment.systemPackages = with pkgs; [
    wakeonlan
    uv
    python312
    nodejs_24
    nodePackages.yarn
    nodePackages.pnpm
  ];

  chrisportela = {
    enableStatsApp = true;
  };

  security.pki.certificateFiles = [
    ../../nixos/modules/cafecitocloud/cafecitocloud-root_ca.crt
  ];

  nix.settings.connect-timeout = "5";

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 4;
}
