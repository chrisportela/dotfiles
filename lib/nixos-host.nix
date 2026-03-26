# lib/nixos-host.nix
# Factory function for NixOS host configurations. Provides shared structure
# and common defaults so hosts only need to specify what's different.
#
# Usage in flake.nix:
#   mkHost = (import ./lib/nixos-host.nix) { inherit inputs self; };
#   nixosConfigurations.ada = mkHost { ... };
{ inputs, self }:
{
  hostName,
  system ? "x86_64-linux",
  nixos ? inputs.nixpkgs-unstable,
  overlays ? [ ],
  stateVersion,
  extraModules ? [ ],
  hostModule,
}:
nixos.lib.nixosSystem {
  inherit system;

  specialArgs = {
    inherit inputs system overlays;
    nixpkgs = nixos;
  };

  modules = [
    inputs.agenix.nixosModules.default
    inputs.disko.nixosModules.disko
    inputs.vscode-server.nixosModules.default
    self.nixosModules.default
  ]
  ++ extraModules
  ++ [
    # Common defaults shared by all hosts
    (
      { config, lib, pkgs, ... }:
      {
        allowedUnfree = [
          "1password"
          "1password-cli"
        ];

        chrisportela = {
          common.enable = true;
          network = {
            enable = true;
            tailscale = {
              enable = true;
              ssh = true;
            };
          };
        };

        networking = {
          inherit hostName;
          dhcpcd.enable = false;
          useDHCP = false;
          useNetworkd = true;
          networkmanager.enable = true;
          nftables.enable = true;
          nftables.checkRuleset = true;
          firewall = {
            enable = true;
            allowedTCPPorts = config.services.openssh.ports;
            allowedUDPPorts = [ config.services.tailscale.port ];
            trustedInterfaces = [ "tailscale0" ];
          };
        };

        security.sudo.wheelNeedsPassword = false;

        # TPM
        security.tpm2.enable = true;
        security.tpm2.pkcs11.enable = true;
        security.tpm2.tctiEnvironment.enable = true;
        services.pcscd.enable = true;

        # Audio
        services.pulseaudio.enable = false;
        security.rtkit.enable = true;
        services.pipewire = {
          enable = true;
          alsa.enable = true;
          alsa.support32Bit = true;
          pulse.enable = true;
        };

        # Desktop common
        services.xserver.xkb = {
          layout = "us";
          variant = "";
        };
        programs.xwayland.enable = true;
        environment.sessionVariables.NIXOS_OZONE_WL = "1";
        services.printing.enable = false;
        boot.plymouth.enable = true;

        programs._1password.enable = true;
        programs._1password-gui = {
          enable = true;
          polkitPolicyOwners = [ "cmp" ];
        };

        time.timeZone = lib.mkDefault "America/New_York";

        # Common packages
        environment.systemPackages = with pkgs; [
          btop
          lm_sensors
          pciutils
          mesa-demos
          hdparm
          inetutils
          nftables
          tcpdump
          traceroute
        ];

        # Wait-online: don't block boot on network
        boot.initrd.systemd.network.wait-online.enable = lib.mkDefault false;

        system.stateVersion = stateVersion;
      }
    )

    # Host-specific config
    hostModule
  ];
}
