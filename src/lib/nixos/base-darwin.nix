{ lib, pkgs, ... }: {
  imports = [ ./base.nix ];

  nix = {
    package = pkgs.nixVersions.nix_2_15;

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
