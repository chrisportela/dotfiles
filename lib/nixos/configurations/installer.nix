{ inputs, system ? "x86_64-linux", hostName ? "installer", ... }:
let
  sshKeys = import ../../sshKeys.nix;
  dependencies = [
    self.nixosConfigurations.flamme.config.system.build.toplevel
    self.nixosConfigurations.flamme.config.system.build.diskoScript
    self.nixosConfigurations.flamme.config.system.build.diskoScript.drvPath
    self.nixosConfigurations.flamme.pkgs.stdenv.drvPath
    (self.nixosConfigurations.flamme.pkgs.closureInfo { rootPaths = [ ]; }).drvPath
  ] ++ builtins.map (i: i.outPath) (builtins.attrValues self.inputs);

  closureInfo = pkgs.closureInfo { rootPaths = dependencies; };
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
        (pkgs.writeShellScriptBin "install-nixos-unattended" ''
          set -eux
          # Replace "/dev/disk/by-id/some-disk-id" with your actual disk ID
          exec ${pkgs.disko}/bin/disko-install --flake "${self}#flamme"
        '')
      ];

      environment.etc."install-closure".source = "${closureInfo}/store-paths";

      users.groups.nix = { };
      users.users.nix = {
        isSystemUser = true;
        group = "nix";
        openssh.authorizedKeys.keys = sshKeys.default;
      };
    })
  ];
}
