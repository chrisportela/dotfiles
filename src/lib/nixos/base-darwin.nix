{ lib, pkgs, ... }: {
  imports = [ ./base.nix ];

  nix = {
    configureBuildUsers = true;
    settings = {
      sandbox = lib.mkDefault "relaxed";
      trusted-users = [ "cmp" ];
      experimental-features = [ "nix-command" "flakes" ];
    };
  };

  environment.systemPackages = with pkgs; [ ];

  system.stateVersion = lib.mkDefault 4;
}
