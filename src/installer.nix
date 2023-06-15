{ pkgs, system, nixosGenerate, nixpkgs_overlay, ... }:
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
      openssh.authorizedKeys.keys = [
        "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBLKmP5UUboT3SkiyHzY81/7UGG0SrVcSWxywkD8lpxYznrFz2uWT6zGfiQNj8FrLSwrh/AthIZJfe0LvbKEtTq8= home@secretive.cp-mba.local"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII5kFjpHHMhPxXAp54egnvuGVidd0g83jrw9AzD3AB5N cp@cp-win1"
      ];
    };
  };
in
nixosGenerate {
  system = pkgs.stdenv.system;
  modules = [
    nixpkgs_overlay
    nixosConfig
  ];
  format = "install-iso";
}
