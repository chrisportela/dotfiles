{ pkgs, ... }: {
  imports = [
    ../../common/home.nix
    ../../lib/wakedesktop.nix
  ];
  home.username = "deck";
  home.packages = with pkgs; [
    #tools
    exiftool
    pre-commit
    deploy-rs
  ];
}
