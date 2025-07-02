{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "nvme"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [
    "kvm-intel"
    "i2c-dev"
    "nvidia-uvm" # For ollama to use GPU properly
  ];
  boot.extraModulePackages = [ ];
  boot.supportedFilesystems = [
    "ntfs"
    "ext4"
    "vfat"
    "zfs"
  ];
  boot.zfs = {
    extraPools = [
      "spool"
      "tank"
    ];
    requestEncryptionCredentials = [
      "spool"
      "spool/docker"
      "spool/home"
      "tank/main"
    ];
    forceImportRoot = false;
  };

  # Bootloader.
  boot.loader = {
    efi = {
      canTouchEfiVariables = true;
      efiSysMountPoint = "/boot";
    };

    grub = {
      enable = true;
      configurationLimit = 10;
      efiSupport = true;
      # efiInstallAsRemovable = true;
      devices = [ "nodev" ];
      # timeoutStyle = "countdown";
      default = "saved"; # use last option booted

      extraEntries = ''
        menuentry 'Windows' --class windows --class os {
          insmod part_gpt
          insmod fat
          search --no-floppy --fs-uuid --set=root BE3A-DC27
          chainloader /efi/Microsoft/Boot/bootmgfw.efi
        }
      '';
    };
  };

  time.hardwareClockInLocalTime = true;

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-uuid/a0e68cd1-b6e7-4568-b2d9-f5253a34cb76";
      fsType = "ext4";
    };

    "/boot" = {
      device = "/dev/disk/by-uuid/E6BE-1E5C";
      fsType = "vfat";
    };
  };

  swapDevices = [ { device = "/dev/disk/by-uuid/bcf75db2-0312-4d27-958e-bb608604caf4"; } ];

  boot.kernel.sysctl = {
    "vm.swappiness" = 80;
  };

  zramSwap = {
    enable = true;
    priority = 5;
    algorithm = "zstd";
    memoryPercent = 100;
  };

  # Enable OpenGL
  hardware.graphics = {
    enable = true;
    #driSupport32Bit = true;
    extraPackages = with pkgs; [
      # onevpl-intel-gpu
    ];
  };

  # https://nixos.wiki/wiki/Intel_Graphics#12th_Gen_(Alder_Lake)
  #boot.kernelParams = [ "i915.force_probe=4680" ];

  # Load nvidia driver for Xorg and Wayland
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {

    # Modesetting is required.
    modesetting.enable = true;

    # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
    powerManagement.enable = true;
    # Fine-grained power management. Turns off GPU when not in use.
    # Experimental and only works on modern Nvidia GPUs (Turing or newer).
    powerManagement.finegrained = false;

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

    # Possible fix for discord crashing?
    nvidiaPersistenced = false;

    prime = {
      sync.enable = false;
      offload.enable = false;
      nvidiaBusId = "PCI:1:0:0";
      intelBusId = "PCI:0:2:0";
    };

    # Optionally, you may need to select the appropriate driver version for your specific GPU.
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  hardware.nvidia-container-toolkit.enable = lib.mkIf config.virtualisation.docker.enable true;

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault false;
  networking.interfaces.enp6s0.useDHCP = lib.mkDefault true;
  networking.interfaces.wlo1.useDHCP = lib.mkDefault true;

  services.autosuspend = {
    enable = false;
    settings = {
      enable = true;
      interval = 30; # seconds
      idle_time = 120; # seconds
    };

    checks = {
      RemoteUsers = {
        class = "Users";
        name = ".*";
        terminal = ".*";
        host = "[0-9].*";
      };

      TmuxUsers = {
        class = "Users";
        name = ".*";
        terminal = ".*";
        host = "localhost";
      };

      LocalUsers = {
        class = "Users";
        name = ".*";
        terminal = ".*";
        host = "localhost";
      };
    };

    wakeups = {
      Systemd-Timer.match = "^(?!.*logrotate).*";
    };
  };
  services.thermald.enable = true;

  # Thunderbolt
  # https://nixos.wiki/wiki/Thunderbolt#Enroll_Thunderbolt_devices
  services.hardware.bolt.enable = true;

  nixpkgs.hostPlatform = "x86_64-linux";
  powerManagement.cpuFreqGovernor = "performance";
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = config.hardware.enableRedistributableFirmware;
}
