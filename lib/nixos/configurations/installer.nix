{ inputs
, system ? "x86_64-linux"
, hostName ? "installer"
, ...
}:
inputs.nixpkgs.lib.nixosSystem {
  inherit system;

  modules = [
    inputs.nixos-generators.nixosModules.all-formats
    "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
    ({ pkgs, lib, ... }: {

      # nixpkgs.hostPlatform.system = system;
      networking.hostName = hostName;

      boot.loader.timeout = lib.mkOverride 10 10;
      documentation.enable = lib.mkOverride 10 false;
      documentation.nixos.enable = lib.mkOverride 10 false;

      boot.initrd.systemd.enable = lib.mkForce false;

      system.disableInstallerTools = lib.mkOverride 10 false;

      systemd.services.sshd.wantedBy = pkgs.lib.mkOverride 10 [ "multi-user.target" ];

      users.groups.nix = {};
      users.users.nix = {
        isSystemUser = true;
        group = "nix";
        openssh.authorizedKeys.keys = (import ../../sshKeys.nix).cmp;
      };
    })
  ];
}
