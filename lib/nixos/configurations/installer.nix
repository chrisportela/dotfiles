{
  inputs,
  system ? "x86_64-linux",
  hostName ? "installer",
  overlays ? [ ],
  ...
}:
let
  sshKeys = import ../../sshKeys.nix;
in
inputs.nixos.lib.nixosSystem {
  inherit system;

  specialArgs = { inherit system inputs overlays; };

  modules = [
    inputs.nixos-generators.nixosModules.all-formats
    # "${inputs.nixos}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
    "${inputs.nixos}/nixos/modules/installer/cd-dvd/installation-cd-graphical-gnome.nix"
    ../modules/nixpkgs.nix
    (
      { pkgs, lib, ... }:
      {
        nixpkgs.config.allowUnfreePredicate = _: true;

        # nixpkgs.hostPlatform.system = system;
        networking.hostName = hostName;

        boot.loader.timeout = lib.mkOverride 10 10;
        documentation.enable = lib.mkOverride 10 false;
        documentation.nixos.enable = lib.mkOverride 10 false;

        boot.initrd.systemd.enable = lib.mkForce false;

        system.disableInstallerTools = lib.mkOverride 10 false;

        systemd.services.sshd.wantedBy = pkgs.lib.mkOverride 10 [ "multi-user.target" ];

        boot.kernel.sysctl = {
          "vm.swappiness" = 133;
        };

        zramSwap = {
          enable = true;
          priority = 5;
          algorithm = "zstd";
          memoryPercent = 50;
        };

        environment.systemPackages = with pkgs;[
          inputs.disko.packages.${system}.disko
          inputs.disko.packages.${system}.disko-install
          btop
          htop
          nvtopPackages.full
          psmisc
          rclone
          reptyr
          rmlint
          lm_sensors
          pciutils
          inetutils
          nftables
          tcpdump
          traceroute
          wget
          curl
          hdparm
          smartmontools
          f3
          e2fsprogs
        ];

        users.users.nixos = {
          openssh.authorizedKeys.keys = sshKeys.default;
        };
      }
    )
  ];
}
