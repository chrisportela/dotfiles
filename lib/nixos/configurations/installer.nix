{ inputs
, system ? "x86_64-linux"
, hostName ? "installer"
, ...
}:
inputs.nixos.lib.nixosSystem {
  inherit system;

  modules = [
    inputs.nixos-generators.nixosModules.all-formats
    "${inputs.nixos}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
    ({ pkgs, lib, ... }: {

      # nixpkgs.hostPlatform.system = system;
      networking.hostName = hostName;

      boot.loader.timeout = lib.mkOverride 10 10;
      documentation.enable = lib.mkOverride 10 false;
      documentation.nixos.enable = lib.mkOverride 10 false;

      boot.initrd.systemd.enable = lib.mkForce false;

      system.disableInstallerTools = lib.mkOverride 10 false;

      systemd.services.sshd.wantedBy = pkgs.lib.mkOverride 10 [ "multi-user.target" ];

      nix = {
        package = pkgs.nixVersions.latest;
        registry.nixpkgs.flake = inputs.nixos;

        settings = {
          experimental-features = [ "nix-command" "flakes" ];
          sandbox = true;
          extra-trusted-public-keys = [
            "binarycache.cp-mba.local:xH/m5WHjOty8a0/n27WSKGhNC0eDf/HX6GREG+G6czM="
            "cache.cp-mba.local-1:YJIH05Ett5Tcq2eEyfroindEQdpwBG5F5f7ztZ+gFCw="
          ];
        };
      };

      users.groups.nix = { };
      users.users.nix = {
        isSystemUser = true;
        group = "nix";
        openssh.authorizedKeys.keys = (import ../../sshKeys.nix).cmp;
      };
    })
  ];
}
