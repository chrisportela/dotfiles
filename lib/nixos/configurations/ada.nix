{ inputs, overlays ? [ ], system ? "x86_64-linux", ... }:
let
  nginx = { ... }: { };
in
inputs.nixos.lib.nixosSystem {
  inherit system;

  specialArgs = {
    inherit inputs system;
    nixpkgs = inputs.nixos;
  };

  modules = [
    inputs.vscode-server.nixosModules.default
    ../hardware/ada.nix

    ../modules/nixpkgs.nix
    ../modules/common.nix
    ../modules/network.nix
    ../modules/openssh.nix
    ../modules/cafecitocloud
    ../modules/gaming.nix
    ../modules/local-llm

    ({ pkgs, config, lib, ... }: {

      allowedUnfree = [
        "1password"
        "1password-cli"
        "ookla-speedtest"

        # Must include because gaming is only enabled in desktop mode
        "nvidia-persistenced"
        "nvidia-settings"
        "nvidia-x11"
      ];

      cafecitocloud.enable = true;
      chrisportela = {
        common.enable = true;
        network = {
          enable = true;
          speedtest-utils = true;
          tailscale = {
            enable = true;
            ssh = true;
          };
        };
        gaming.enable = lib.mkDefault false;
        local-llm.enable = true;
      };

      services.pcscd.enable = true; # For configuring Yubikey

      # Enable networking
      networking = {
        hostName = "ada";
        hostId = "5bc6e263";

        # wireless.enable = true; # Enables wireless support via wpa_supplicant.
        dhcpcd.enable = false;
        useDHCP = false;
        useNetworkd = true;
        networkmanager.enable = true;

        interfaces.enp6s0.useDHCP = true;
        interfaces.wlo1.useDHCP = true;

        nftables.enable = true;
        nftables.checkRuleset = true;
        firewall = {
          enable = true;
          allowedTCPPorts = config.services.openssh.ports;
          allowedUDPPorts = [ config.services.tailscale.port ];
          trustedInterfaces = [ "tailscale0" "docker0" ];
        };
      };

      # Prevent wait-online from stopping boot or switching config
      boot.initrd.systemd.network.wait-online.enable = false;
      systemd.network.wait-online.enable = false;

      environment.systemPackages = with pkgs; [
        btop
        nvtopPackages.full

        # Hardware
        lm_sensors
        pciutils
        glxinfo
        hdparm

        # Network
        inetutils
        nftables
        tcpdump
        traceroute
      ];

      time.timeZone = lib.mkForce "America/New_York";

      specialisation.desktop.configuration = {
        chrisportela.gaming.enable = true;

        services.xserver = {
          # Enable the X11 windowing system.
          # enable = true;

          dpi = 180;

          # Configure keymap in X11
          xkb = {
            layout = "us";
            variant = "";
          };

          # Enable the KDE Plasma Desktop Environment.
          # desktopManager.plasma5.enable = true;
          # desktopManager.plasma5.useQtScaling = true;
        };

        # plasma6
        services.desktopManager.plasma6.enable = true;

        services.displayManager = {
          sddm.enable = true;
          sddm.enableHidpi = true;
          sddm.settings = {
            General = {
              GreeterEnvironment = "QT_SCREEN_SCALE_FACTORS=2,QT_FONT_DPI=192";
            };
          };
          sddm.wayland.enable = true;
        };
        programs.xwayland.enable = true;

        services.printing.enable = false;

        # Enable sound with pipewire.
        sound.enable = true;
        hardware.pulseaudio.enable = false;
        security.rtkit.enable = true;
        services.pipewire = {
          enable = true;
          alsa.enable = true;
          alsa.support32Bit = true;
          pulse.enable = true;
        };

        programs._1password.enable = true;
        programs._1password-gui = {
          enable = true;
          polkitPolicyOwners = [ "cmp" ];
        };
        security.pam.services.kwallet.enableKwallet = true;

        virtualisation = {
          virtualbox.host.enable = true;
          libvirtd.enable = true;
        };
        programs.dconf.enable = true; # For libvirtd

        environment.sessionVariables = {
          NIXOS_OZONE_WL = "1";
        };

        users.users.cmp = {
          extraGroups = [
            "libvirtd"
          ];

          packages = with pkgs; [
            firefox
            kate
            virt-manager
          ];
        };

      };

      boot.plymouth = {
        enable = true;
        # logo = "";
        # theme = "bgrt";
      };

      services.vscode-server.enable = lib.mkDefault true;

      services.zfs = {
        trim = {
          enable = true;
          # interval = "daily";
        };

        autoScrub = {
          enable = true;
          pools = [ "spool" "tank" ];
          interval = "monthly";
        };

      };

      virtualisation = {
        docker = {
          enable = true;
          # enableNvidia = true;# Deprecated
          storageDriver = "zfs";
        };
        # TODO: switch to podman
        oci-containers.backend = "docker";
      };

      services.nginx.enable = true;
      users.users.nginx.extraGroups = [ "acme" ];

      users.users.cmp = {
        extraGroups = [
          "networkmanager"
          "wheel"
          "libvirtd"
          "ddc"
          "docker"
        ];

        packages = with pkgs; [ ];
      };

      system.stateVersion = "23.05";
    })
  ];
}
