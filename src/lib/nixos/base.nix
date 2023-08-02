{ lib, config, pkgs, vscode-server, ... }: {
  imports = [ ];

  nix = {
    package = pkgs.nixVersions.nix_2_16;
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      trusted-public-keys = [
        "binarycache.cp-mba.local:xH/m5WHjOty8a0/n27WSKGhNC0eDf/HX6GREG+G6czM="
        "cache.cp-mba.local-1:YJIH05Ett5Tcq2eEyfroindEQdpwBG5F5f7ztZ+gFCw="
      ];
    };
  };

  nixpkgs.config.allowUnfree = true;

  environment.pathsToLink = [ "/share/nix-direnv" ];
  environment.systemPackages = with pkgs; [
    curl
    git
    htop
    neovim
    nixpkgs-fmt
    openssl_3
    wget
  ];

}
