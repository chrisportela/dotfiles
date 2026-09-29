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
    # Heuristic overcommit. Layer 2 (per-cgroup MemoryMax via
    # chrisportela.memory-protection) is the actual protection against
    # runaways; mode 2 was redundant after cgroup containment landed and
    # was blocking legitimate sci-python and docker builds.
    # See docs/superpowers/specs/2026-04-29-ada-memory-tuning-design.md
    # for the four-layer architecture.
    "vm.overcommit_memory" = 0;

    # zswap+Optane is fast enough that aggressive anon-prefer (was 133 with
    # zram) is unnecessary; 100 keeps anon and file-cache reclaim balanced.
    "vm.swappiness" = 100;

    # Wake kswapd at ~1% free RAM (~1.3GB on 128GB) instead of the default
    # 0.1% (~128MB). Default is too late on big-memory boxes. Was 200 (2%)
    # on 64GB; halved at the 128GB upgrade to keep the same absolute gap.
    "vm.watermark_scale_factor" = 100;

    # Bias toward keeping file cache under pressure. Helps nix-store reads
    # + ZFS ARC interactions.
    "vm.vfs_cache_pressure" = 50;
  };

  zramSwap.enable = false;

  # zswap: compressed-page pool in front of Optane swap. Hot pages stay
  # compressed in RAM, cold pages spill to the 4×16GB Optane swap
  # partitions. Every zswapped page still reserves a swap slot, so the pool
  # can't usefully exceed 64GB ÷ compression ratio (~3:1 zstd ≈ 21GB);
  # 20% of 128GB ≈ 25.6GB matches the old 40%-of-64GB ceiling.
  boot.kernelParams = [
    "zswap.enabled=1"
    "zswap.compressor=zstd"
    "zswap.zpool=zsmalloc"
    "zswap.max_pool_percent=20"
    "zswap.shrinker_enabled=Y"

    # Cap ZFS ARC at 32GiB (~25% of RAM). OpenZFS >= 2.3 defaults c_max to
    # ~RAM-1G on Linux, and ARC is NOT charged to any cgroup — it's
    # invisible to the memory-protection ceilings below and only shrinks
    # reactively, lagging behind PSI/oomd. 32GiB covers zroot + tank
    # metadata and hot data; leaves the rest predictable for workloads.
    # Kernel param (not modprobe.d) so it applies when zfs.ko loads in
    # stage 1 for the ZFS root.
    "zfs.zfs_arc_max=34359738368"
  ];

  # systemd-oomd: userspace OOM killer using PSI (pressure stall) metrics.
  # Acts on cgroup-level pressure before the kernel OOM killer fires.
  # This is what Fedora/RHEL ship — tighter systemd integration than earlyoom.
  systemd.oomd = {
    enable = true;
    enableRootSlice = true;
    enableUserSlices = true;
    enableSystemSlice = true;
    settings.OOM = {
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
  #
  # Ceilings are RAM-only (cgroup v2 memory.max/high; memory.swap.max stays
  # "max"), but reclaim at either limit swaps out rather than killing. So:
  #   memoryHigh < usable RAM minus the always-on floor → a runaway gets
  #     throttled and pushed into zswap/Optane before host RAM runs out.
  #   memoryMax > RAM, sized against 125GiB RAM + 64GiB swap ≈ 189GiB →
  #     the group can keep swapping; the kernel OOM-kills only once swap is
  #     nearly gone (oomd's SwapUsedLimit=90% usually acts first).
  # Always-on floor measured 2026-09-28: llama ~10G, microvms ~4G (hermes
  # up to 8G), docker services ~4G, rest of system.slice ~5G ≈ 23G, plus
  # ARC (capped 32G above, shrinkable to ~4G c_min). One heavy group at a
  # time is assumed; oomd arbitrates if several go heavy together.
  chrisportela.memory-protection = {
    enable = true;
    nixDaemon = {
      enable = true;
      memoryMax = "160G";
      memoryHigh = "96G";
    };
    dockerSlice = {
      enable = true;
      memoryMax = "160G";
      memoryHigh = "96G";
    };
    userSlice = {
      enable = true;
      # Higher: KDE + browser + Steam + ad-hoc builds share this slice.
      memoryMax = "176G";
      memoryHigh = "104G";
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
