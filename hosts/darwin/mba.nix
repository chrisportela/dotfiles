{ lib, config, pkgs, ... }: {
  chrisportela = {
    darwin-common.enable = true;
    stats.enable = true;
  };

  environment.systemPackages = with pkgs; [
    wakeonlan
    uv
    python312
    nodejs_24
    yarn
    pnpm
    _1password-cli
  ];

  allowedUnfree = [ "1password-cli" ];

  security.pki.certificateFiles =
    [ ../../../modules/nixos/cafecitocloud/cafecitocloud-root_ca.crt ];

  nix.settings.connect-timeout = "5";

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 4;
}
