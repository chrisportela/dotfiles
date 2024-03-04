{ inputs, nixosModules, overlays ? [ ], ... }:
let
  hardwareConfig = import ../hardware/ada.nix;
in
inputs.nixpkgs.lib.nixosSystem {
  specialArgs = {
    inherit inputs overlays;
    nixpkgs = inputs.nixpkgs;
  };

  modules = [
    inputs.vscode-server.nixosModules.default
    nixosModules.common
    # nixosModules.ddc  # Possible source of udev boot slowness
    nixosModules.dualboot
    nixosModules.nixpkgs
    nixosModules.openssh
    hardwareConfig

    ({ pkgs, config, lib, ... }: {

      nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
        "steam"
        "steam-original"
        "steam-run"
        "nvidia-persistenced"
        "nvidia-settings"
        "nvidia-x11"
        "1password"
        "1password-cli"
        "ookla-speedtest"
      ];

      security.pki.certificates = [
        ''
          Root Cafecito Cloud CA
          =======================
          ${builtins.readFile ../../cafecitocloud-root_ca.crt}
        ''
        ''
          YubiKey 4 Cafecito Cloud Intermediate CA
          =======================
          ${builtins.readFile ../../cafecitocloud-yubikey4-intermediate_ca.crt}
        ''
      ];

      # Enable networking
      networking = {
        hostName = "ada";
        hostId = "5bc6e263";

        # wireless.enable = true; # Enables wireless support via wpa_supplicant.
        dhcpcd.enable = false;
        useDHCP = false;
        useNetworkd = true;
        networkmanager.enable = true;

        # nameservers = [ "1.1.1.1#853" ];

        interfaces.enp6s0.useDHCP = true;
        interfaces.wlo1.useDHCP = true;

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
        virt-manager

        # Hardware
        ddcutil
        ddcui
        lm_sensors

        # Network
        inetutils
        ipcalc
        iperf3
        nftables
        tcpdump
        traceroute
        fast-cli
        ookla-speedtest
        speedtest-cli
      ];


      services.tailscale = {
        enable = true;
        package = pkgs.tailscale;
      };

      services.resolved = {
        enable = true;
        fallbackDns = [
          "1.1.1.1#853"
        ];
        dnssec = "false";
      };

      time.timeZone = "America/New_York";

      services.xserver = {
        # Enable the X11 windowing system.
        enable = true;

        dpi = 180;

        # Configure keymap in X11
        xkb = {
          layout = "us";
          variant = "";
        };

        # Enable the KDE Plasma Desktop Environment.
        displayManager.sddm.enable = true;
        displayManager.sddm.wayland.enable = false;
        desktopManager.plasma5.enable = true;
        desktopManager.plasma5.useQtScaling = true;
      };
      programs.xwayland.enable = true;

      # Enable CUPS to print documents.
      services.printing.enable = true;

      # Enable sound with pipewire.
      sound.enable = true;
      hardware.pulseaudio.enable = false;
      security.rtkit.enable = true;
      services.pipewire = {
        enable = true;
        alsa.enable = true;
        alsa.support32Bit = true;
        pulse.enable = true;
        # If you want to use JACK applications, uncomment this
        # jack.enable = true;

        # use the example session manager (no others are packaged yet so this is enabled by default, no
        # need to redefine it in your config for now)
        # wireplumber.enable = true;
      };

      programs.neovim = {
        enable = true;
        viAlias = true;
        vimAlias = true;
      };

      services.vscode-server.enable = true;

      programs._1password.enable = true;
      programs._1password-gui.enable = true;
      programs._1password-gui.polkitPolicyOwners = [ "cmp" ];
      security.pam.services.kwallet.enableKwallet = true;

      virtualisation = {
        docker = {
          enable = false;
          enableNvidia = true;
          storageDriver = "zfs";
        };
        virtualbox.host = {
          enable = true;
        };
        libvirtd.enable = true;
      };
      programs.dconf.enable = true; # For libvirtd

      programs.steam = {
        enable = true;
        remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
        dedicatedServer.openFirewall = false; # Open ports in the firewall for Source Dedicated Server
      };

      environment.sessionVariables = {
        STEAM_FORCE_DESKTOPUI_SCALING = "2";
      };

      users.users.cmp = {
        extraGroups = [
          "networkmanager"
          "wheel"
          "libvirtd"
          "ddc"
          "docker"
        ];

        packages = with pkgs; [ firefox kate ];
      };

      system.stateVersion = "23.05";
    })
  ];
}
