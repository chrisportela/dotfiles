{ inputs, nixosModules, overlays, ... }:
let
  hardwareConfig = { config, lib, pkgs, modulesPath, ... }: {
    imports =
      [
        (modulesPath + "/installer/scan/not-detected.nix")
      ];

    boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod" ];
    boot.initrd.kernelModules = [ ];
    boot.kernelModules = [ "kvm-intel" "i2c-dev" ];
    boot.extraModulePackages = [ ];
    boot.supportedFilesystems = [ "ntfs" "ext4" "vfat" "zfs" ];
    boot.zfs.extraPools = [ "spool" ];
    boot.zfs.requestEncryptionCredentials = [
      "spool"
      "spool/docker"
      "spool/home"
    ];
    boot.zfs.forceImportRoot = false;

    fileSystems = {
      "/" = {
        device = "/dev/disk/by-uuid/a0e68cd1-b6e7-4568-b2d9-f5253a34cb76";
        fsType = "ext4";
      };

      "/boot" =
        {
          device = "/dev/disk/by-uuid/E6BE-1E5C";
          fsType = "vfat";
        };
    };

    swapDevices = [{ device = "/dev/disk/by-uuid/bcf75db2-0312-4d27-958e-bb608604caf4"; }];

    # Enable OpenGL
    hardware.opengl = {
      enable = true;
      driSupport = true;
      driSupport32Bit = true;
    };

    # Load nvidia driver for Xorg and Wayland
    services.xserver.videoDrivers = [ "nvidia" ];

    hardware.nvidia = {

      # Modesetting is required.
      modesetting.enable = true;

      # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
      powerManagement.enable = false;
      # Fine-grained power management. Turns off GPU when not in use.
      # Experimental and only works on modern Nvidia GPUs (Turing or newer).
      #    powerManagement.finegrained = true;

      # Use the NVidia open source kernel module (not to be confused with the
      # independent third-party "nouveau" open source driver).
      # Support is limited to the Turing and later architectures. Full list of
      # supported GPUs is at:
      # https://github.com/NVIDIA/open-gpu-kernel-modules#compatible-gpus
      # Only available from driver 515.43.04+
      # Do not disable this unless your GPU is unsupported or if you have a good reason to.
      open = true;

      # Enable the Nvidia settings menu,
      # accessible via `nvidia-settings`.
      nvidiaSettings = true;

      # Optionally, you may need to select the appropriate driver version for your specific GPU.
      package = config.boot.kernelPackages.nvidiaPackages.stable;
    };

    # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
    # (the default) this is the recommended approach. When using systemd-networkd it's
    # still possible to use this option, but it's recommended to use it in conjunction
    # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
    networking.useDHCP = lib.mkDefault true;
    networking.interfaces.enp6s0.useDHCP = lib.mkDefault true;
    networking.interfaces.wlo1.useDHCP = lib.mkDefault true;

    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
    powerManagement.cpuFreqGovernor = lib.mkDefault "schedutil";
    hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  };
in
inputs.nixpkgs.lib.nixosSystem {
  system = "aarch64-linux";
  specialArgs = {
    inherit inputs overlays;
    nixpkgs = inputs.nixpkgs;
  };
  modules = [
    inputs.vscode-server.nixosModules.default
    nixosModules.common
    nixosModules.nixpkgs
    nixosModules.openssh
    hardwareConfig
    ({ pkgs, config, lib, ... }: {
      # Bootloader.
      boot.loader.systemd-boot = {
        enable = true;
        consoleMode = "max";

        configurationLimit = 5;

        memtest86.enable = true;

        #         extraFiles = {
        #           "esp/windows.nsh" = lib.writeTextFile "esp_windows.nsh" ''
        #           HD0a66666a2:EFI\Microsoft\Boot\Bootmgfw.efi
        #           '';
        #         };
        #
        #         extraEntries = {
        #           "Windows" = ''
        #           title Windows 11
        #           efi /shellx64.efi
        #           options -nointerrupt -noconsolein -noconsoleout windows.nsh
        #           '';
        #         };
      };
      boot.loader.efi.canTouchEfiVariables = true;

      nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
        "steam"
        "steam-original"
        "steam-run"
      ];

      programs.steam = {
        enable = true;
        remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
        dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
      };

      environment.sessionVariables = {
        STEAM_FORCE_DESKTOPUI_SCALING = "2";
      };

      networking.hostName = "ada";
      networking.hostId = "5bc6e263";
      # networking.wireless.enable = true; # Enables wireless support via wpa_supplicant.

      # Enable networking
      networking.useNetworkd = true;
      networking.dhcpcd.enable = false;
      networking.useDHCP = false;
      networking.networkmanager.enable = true;
      networking.networkmanager.dns = lib.mkForce "default";
      networking.nameservers = [
        "100.100.100.100"
        "127.0.0.1"
        "1.1.1.1#853"
      ];
      networking.resolvconf.dnsExtensionMechanism = false;
      systemd.network.wait-online.anyInterface = true;

      environment.systemPackages = with pkgs; [
        inetutils
        ipcalc
        iperf3
        nftables
        tcpdump
        traceroute
        fast-cli
        ookla-speedtest
        speedtest-cli
        virt-manager
        ddcutil
        ddcui
        lm_sensors
      ];

      services.udev.extraRules = ''
        KERNEL=="i2c-[0-9]*", GROUP="ddc", MODE="0660", PROGRAM="${pkgs.ddcutil}/bin/ddcutil --bus=%n getvcp 0x10"
      '';

      services.ddccontrol.enable = true;

      networking.nftables.enable = lib.mkDefault true;
      networking.nftables.checkRuleset = lib.mkDefault true;
      networking.firewall = {
        enable = true;
        allowedTCPPorts = config.services.openssh.ports;
        allowedUDPPorts = [ config.services.tailscale.port ];
        trustedInterfaces = [ "tailscale0" ];
      };

      services.tailscale = {
        enable = true;
        package = pkgs.tailscale;
      };

      services.resolved = {
        enable = true;
        fallbackDns = [
          "100.100.100.100"
          "127.0.0.1"
          "1.1.1.1#853"
        ];
        dnssec = "false";
      };

      services.unbound = {
        enable = true;
        resolveLocalQueries = true;
        localControlSocketPath = "/run/unbound/unbount.ctl";
        enableRootTrustAnchor = true;
        settings.server.interface = [ "127.0.0.1" ];
      };

      # Set your time zone.
      time.timeZone = "America/New_York";

      # Select internationalisation properties.
      i18n.defaultLocale = "en_US.UTF-8";

      i18n.extraLocaleSettings = {
        LC_ADDRESS = "en_US.UTF-8";
        LC_IDENTIFICATION = "en_US.UTF-8";
        LC_MEASUREMENT = "en_US.UTF-8";
        LC_MONETARY = "en_US.UTF-8";
        LC_NAME = "en_US.UTF-8";
        LC_NUMERIC = "en_US.UTF-8";
        LC_PAPER = "en_US.UTF-8";
        LC_TELEPHONE = "en_US.UTF-8";
        LC_TIME = "en_US.UTF-8";
      };


      services.xserver = {
        # Enable the X11 windowing system.
        enable = true;

        dpi = 180;

        # Configure keymap in X11
        layout = "us";
        xkbVariant = "";

        # Enable the KDE Plasma Desktop Environment.
        displayManager.sddm.enable = true;
        desktopManager.plasma5.enable = true;
        desktopManager.plasma5.useQtScaling = true;
      };


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
        # If you want to use JACK applications, uncomment this jack.enable = true;

        # use the example session manager (no others are packaged yet so this is enabled by default, no
        # need to redefine it in your config for now)
        #wireplumber.enable = true;
      };

      programs.neovim = {
        enable = true;
        viAlias = true;
        vimAlias = true;
      };

      services.vscode-server.enable = true;

      programs._1password.enable = true;
      programs._1password-gui.enable = true;
      programs._1password-gui.polkitPolicyOwners = ["cmp"];
      security.pam.services.kwallet.enableKwallet = true;

      virtualisation.docker = {
        enable = true;
        enableNvidia = true;
        storageDriver = "zfs";
      };

      security.pki.certificates = [
        ''
          Root Cafecito Cloud CA
          =======================
          ${builtins.readFile ../lib/cafecitocloud-root_ca.crt}
        ''
        ''
          YubiKey 4 Cafecito Cloud Intermediate CA
          =======================
          ${builtins.readFile ../lib/cafecitocloud-yubikey4-intermediate_ca.crt}
        ''
      ];

      virtualisation.libvirtd.enable = true;
      programs.dconf.enable = true;


      users.groups.ddc = { };
      # Define a user account. Don't forget to set a password with ‘passwd’.
      users.users.cmp = {
        isNormalUser = true;
        description = "Chris Portela";
        extraGroups = [
          "networkmanager"
          "wheel"
          "libvirtd"
          "ddc"
          "docker"
        ];
        packages = with pkgs; [
          firefox
          kate

          #  thunderbird
        ];

      };

      # Allow unfree packages
      nixpkgs.config.allowUnfree = true;

      system.stateVersion = "23.05";
    })
  ];
}
