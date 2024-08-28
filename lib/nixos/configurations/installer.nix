{ inputs, system ? "x86_64-linux", hostName ? "installer", ... }:
let
  sshKeys = import ../../sshKeys.nix;
in
inputs.nixos.lib.nixosSystem {
  inherit system;

  modules = [
    inputs.nixos-generators.nixosModules.all-formats
    # "${inputs.nixos}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
    "${inputs.nixos}/nixos/modules/installer/cd-dvd/installation-cd-graphical-gnome.nix"
    ../modules/nixpkgs.nix
    ({ pkgs, lib, ... }: {

      # nixpkgs.hostPlatform.system = system;
      networking.hostName = hostName;

      boot.loader.timeout = lib.mkOverride 10 10;
      documentation.enable = lib.mkOverride 10 false;
      documentation.nixos.enable = lib.mkOverride 10 false;

      boot.initrd.systemd.enable = lib.mkForce false;

      system.disableInstallerTools = lib.mkOverride 10 false;

      systemd.services.sshd.wantedBy = pkgs.lib.mkOverride 10 [ "multi-user.target" ];

      environment.systemPackages = [
        inputs.disko.packages.${system}.disko
        inputs.disko.packages.${system}.disko-install
      ];

      users.groups.nix = { };
      users.users.nix = {
        isSystemUser = true;
        group = "nix";
        openssh.authorizedKeys.keys = sshKeys.default;
      };
    })
  ];
}
