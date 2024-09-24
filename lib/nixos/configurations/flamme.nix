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
    ../hardware/framework.nix

    ../modules/nixpkgs.nix
    ../modules/common.nix
    ../modules/network.nix
    ../modules/openssh.nix
    ../modules/cafecitocloud
    ../modules/gaming.nix

    ({ pkgs, config, lib, ... }: {

      allowedUnfree = [
        "1password"
        "1password-cli"
        "ookla-speedtest"
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
        gaming.enable = true;
      };

      services.pcscd.enable = true; # For configuring Yubikey

      # Enable networking
      networking = {
        hostName = "flamme";
        hostId = "ebcd55e8";

        # Disable basic networking
        wireless.enable = false; # Enables wireless support via wpa_supplicant.
        dhcpcd.enable = false;
        useDHCP = false;

        useNetworkd = true;
        networkmanager.enable = true;

        # interfaces.enp6s0.useDHCP = true;
        # interfaces.wlo1.useDHCP = true;

        nftables.enable = true;
        nftables.checkRuleset = true;
        firewall = {
          enable = true;
          allowedTCPPorts = config.services.openssh.ports;
          allowedUDPPorts = [ config.services.tailscale.port ];
          trustedInterfaces = [ "tailscale0" ];
        };
      };

      # Prevent wait-online from stopping boot or switching config
      boot.initrd.systemd.network.wait-online.enable = false;
      systemd.network.wait-online.enable = false;

      environment.systemPackages = with pkgs; [
        btop

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

      services.xserver = {
        dpi = 180;

        # Configure keymap in X11
        xkb = {
          layout = "us";
          variant = "";
        };
      };

      services.xserver.enable = true;
      services.xserver.desktopManager.gnome.enable = true;
      services.xserver.displayManager.gdm.enable = true;
      # plasma6
      # services.desktopManager.plasma6.enable = true;

      services.displayManager = {
        sddm.enable = false;
        # sddm.enableHidpi = true;
        # sddm.settings = {
        #   General = {
        #     # GreeterEnvironment = "QT_SCREEN_SCALE_FACTORS=2,QT_FONT_DPI=180";
        #   };
        # };
        # sddm.wayland.enable = true;
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
      # security.pam.services.kwallet.enableKwallet = true;

      environment.sessionVariables = {
        NIXOS_OZONE_WL = "1";
      };

      boot.plymouth = {
        enable = true;
        # logo = "";
        # theme = "bgrt";
      };

      # services.zfs = {
      #   trim = {
      #     enable = true;
      #     # interval = "daily";
      #   };

      #   autoScrub = {
      #     enable = true;
      #     pools = [ "zpool" ];
      #     interval = "monthly";
      #   };

      # };

      services.flatpak.enable = true;

      virtualisation = {
        # oci-containers.backend = "podman";
      };

      users.users.cmp = {
        extraGroups = [
          "networkmanager"
          "wheel"
        ];

        packages = with pkgs; [
          firefox
        ];
      };

      system.stateVersion = "24.05";
    })
  ];
}
