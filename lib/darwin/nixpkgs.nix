{ lib, config, overlays, ... }: {
  imports = [ ../nixos/modules/nixpkgs.nix ];

  # Pending https://github.com/NixOS/nixpkgs/issues/55674
  options.allowedUnfree = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
  };

  config = {

    nix = {
      configureBuildUsers = true;

      settings = {
        sandbox = "relaxed";
        trusted-users = [ "root" "@admin" ];
      };

      linux-builder = {
        enable = true;
        ephemeral = true;
        maxJobs = 4;
        config = {
          virtualisation = {
            darwin-builder = {
              diskSize = 40 * 1024;
              memorySize = 8 * 1024;
            };
            cores = 6;
          };
        };
      };
    };

    services.nix-daemon.enable = true;
  };
}
