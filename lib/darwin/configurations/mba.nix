{ lib, config, pkgs, ... }: {
  imports = [
    ../common.nix
    ../nixpkgs.nix
  ];

  environment.systemPackages = with pkgs; [
    wakeonlan
  ];

  nix.settings.connect-timeout = "5";

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 4;
}
