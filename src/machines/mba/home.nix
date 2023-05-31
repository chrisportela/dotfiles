{ pkgs, config, ... }: {
  imports = [
    ../../common/home.nix
    ../../lib/wakedesktop.nix
  ];

  home.username = "cmp";
  home.homeDirectory = "/Users/${config.home.username}";

  home.packages = with pkgs; [
    #language stuff
    nodejs
    yarn
    go
    poetry

    #tools
    exiftool
    pre-commit
    awscli2
    amazon-ecr-credential-helper
    google-cloud-sdk
    doctl
    backblaze-b2
    deploy-rs
  ];
}
