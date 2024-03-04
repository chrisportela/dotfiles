{ hostName ? "installer", pkgs, system, nixosGenerate, nixpkgs_overlay, ... }:
nixosGenerate {
  inherit system;

  modules = [
    nixpkgs_overlay

    ({ lib, config, modulesPath, ... }: {
      imports = [
        "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
      ];

      nixpkgs.hostPlatform.system = system;
      networking.hostName = hostName;

      boot.loader.timeout = lib.mkOverride 10 10;
      documentation.enable = lib.mkOverride 10 false;
      documentation.nixos.enable = lib.mkOverride 10 false;

      boot.initrd.systemd.enable = lib.mkForce false;

      system.disableInstallerTools = lib.mkOverride 10 false;

      systemd.services.sshd.wantedBy = pkgs.lib.mkOverride 10 [ "multi-user.target" ];

      users.users.nix = {
        isSystemUser = true;
        group = "nix";
        openssh.authorizedKeys.keys = (import ./sshKeys.nix).cmp;
      };
    })
  ];
  format = "install-iso";
}
