{ lib, ... }: with lib; {
  imports = [
    ./base.nix
    ./nix.nix
  ];

  services.nix-daemon.enable = true;

  system.stateVersion = lib.mkDefault 4;
}
