{ pkgs, ... }: {
  imports = [
    ../../common/home.nix
    ../../lib/wakedesktop.nix
  ];
  home.username = "cmp";
  home.packages = with pkgs; [
    #language stuff
    nodejs
    yarn
    go
    poetry

    #tools
    exiftool
    pre-commit
    amazon-ecr-credential-helper
    google-cloud-sdk
    doctl
    backblaze-b2
    deploy-rs

    transmission
    tremc
    stig
  ];
}
