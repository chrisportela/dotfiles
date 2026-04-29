{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    ./disko.nix
  ];

  boot.initrd.systemd.enable = true;
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "nvme"
    "mpt3sas" # for WD drives
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
  boot.zfs = {
    extraPools = [
      # "spool"
      # "tank"
    ];
    forceImportRoot = true;
  };

  # Bootloader.
  boot.loader = {
    efi = {
      canTouchEfiVariables = true;
      # efiSysMountPoint = "/boot";
    };
    systemd-boot = {
      enable = true;
      configurationLimit = 30;
      editor = true;
    };

    # grub = {
    #   enable = true;
    #   configurationLimit = 10;
    #   efiSupport = true;
    #   # efiInstallAsRemovable = true;
    #   devices = [ "nodev" ];
    #   # timeoutStyle = "countdown";
    #   default = "saved"; # use last option booted

    #   extraEntries = ''
    #     menuentry 'Windows' --class windows --class os {
    #       insmod part_gpt
    #       insmod fat
    #       search --no-floppy --fs-uuid --set=root BE3A-DC27
    #       chainloader /efi/Microsoft/Boot/bootmgfw.efi
    #     }
    #   '';
    # };
  };

  time.hardwareClockInLocalTime = true;

  boot.kernel.sysctl = {
    # Validation phase: strict overcommit retained as a backstop while we
    # verify cgroup containment under load. Wide budget (64G swap + 250% × 64G
    # RAM ≈ 224G) lets legitimate sci-python and docker builds proceed.
    # Task 9 of the plan switches this to mode 0 once cgroup containment is
    # validated.
    "vm.overcommit_memory" = 2;
    "vm.overcommit_ratio" = 250;

    # Less aggressive than the previous 133 (which was tuned to push pages
    # into zram). With zswap+Optane, swap is fast enough that we don't need
    # to bias hard.
    "vm.swappiness" = 100;

    # Wake kswapd at ~2% free RAM (~1.3GB on 64GB) instead of the default
    # 0.1% (~64MB). Default is far too late on big-memory boxes; allocations
    # stall before reclaim catches up.
    "vm.watermark_scale_factor" = 200;

    # Bias toward keeping file cache under pressure. Default 100 reclaims
    # dentry/inode cache as aggressively as page cache; 50 keeps file cache
    # longer (helps nix-store reads + ZFS ARC interactions).
    "vm.vfs_cache_pressure" = 50;
  };

  zramSwap.enable = false;

  # zswap: compressed-page pool in front of Optane swap. Hot pages stay
  # compressed in RAM (40% pool ≈ 25.6GB on 64GB), cold pages spill to
  # the 4×16GB Optane swap partitions.
  boot.kernelParams = [
    "zswap.enabled=1"
    "zswap.compressor=zstd"
    "zswap.zpool=zsmalloc"
    "zswap.max_pool_percent=40"
    "zswap.shrinker_enabled=Y"
  ];

  # systemd-oomd: userspace OOM killer using PSI (pressure stall) metrics.
  # Acts on cgroup-level pressure before the kernel OOM killer fires.
  # This is what Fedora/RHEL ship — tighter systemd integration than earlyoom.
  systemd.oomd = {
    enable = true;
    enableRootSlice = true;
    enableUserSlices = true;
    enableSystemSlice = true;
    extraConfig = {
      # Default 30s is too patient on a workstation. 10s catches runaways
      # before interactive responsiveness craters.
      DefaultMemoryPressureDurationSec = "10s";
      # Act when global swap usage crosses 90%. Reaching this on Optane
      # means we've exhausted reclaim budget, not just normal cold-page
      # eviction.
      SwapUsedLimit = "90%";
    };
  };

  # Memory protection: cgroup ceilings + critical-service hardening.
  # See modules/nixos/memory-protection/README.md for layer architecture.
  chrisportela.memory-protection = {
    enable = true;
    nixDaemon = {
      enable = true;
      memoryMax = "90G";
      memoryHigh = "75G";
    };
    dockerSlice = {
      enable = true;
      memoryMax = "90G";
      memoryHigh = "75G";
    };
    userSlice = {
      enable = true;
      memoryMax = "100G";
      memoryHigh = "85G";
    };
    microvmHost = true;
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
