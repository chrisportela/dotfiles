{ pkgs, system, nixosGenerate, pinned_nixpkgs, ... }:
let
  hostName = "installer";

  nixosConfig = { lib, config, modulesPath, ... }: {
    imports = [
      "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
    ];

    nixpkgs.hostPlatform.system = pkgs.stdenv.system;
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
      openssh.authorizedKeys.keys = (import ../sshKeys.nix).cmp;
    };
  };
in
nixosGenerate {
  system = pkgs.stdenv.system;
  modules = [
    pinned_nixpkgs
    nixosConfig
  ];
  format = "install-iso";
}
