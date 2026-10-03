{
  config,
  lib,
  pkgs,
  modulesPath,
  inputs,
  ...
}:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    "${inputs.nixos-hardware}/framework/13-inch/common"
    "${inputs.nixos-hardware}/framework/13-inch/common/intel.nix"
    inputs.disko.nixosModules.disko
    # ../../../modules/nixos/disko/zfs-impermanence.nix
    ../../../modules/nixos/disko/luks-ext4.nix
  ];

  disko.devices.disk.root.device = "/dev/nvme0n1";

  # Need at least 6.9 to make suspend properly
  # Specifically this patch: https://github.com/torvalds/linux/commit/073237281a508ac80ec025872ad7de50cfb5a28a
  boot.kernelPackages = pkgs.linuxPackages_latest;

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "thunderbolt"
    "nvme"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];
  boot.supportedFilesystems = [
    "ntfs"
    "ext4"
    "vfat"
  ];
  # boot.zfs = {
  #   extraPools = [ "zpool" ];
  #   requestEncryptionCredentials = [ "zpool" ];
  #   forceImportRoot = false;
  # };
  # Because need latest kernel and it's not supported yet(?)
  # boot.zfs.package = pkgs.zfs_unstable;

  boot.initrd.systemd.enable = true;

  # Bootloader.
  boot.loader = {
    # efi = {
    #   canTouchEfiVariables = true;
    #   efiSysMountPoint = "/boot";
    # };

    systemd-boot.enable = true;
    systemd-boot.consoleMode = "max";
  };

  # Memory: same four-layer design as ada (see hosts/nixos/ada/hardware.nix
  # and modules/nixos/memory-protection/README.md), sized for 15 GiB RAM.
  boot.kernel.sysctl = {
    # Heuristic overcommit. Per-cgroup ceilings (Layer 2 below) are the real
    # runaway protection; strict mode 2 made legitimate allocations fail.
    "vm.overcommit_memory" = 0;

    # zswap in front of a disk swapfile: balanced anon vs file-cache reclaim.
    # (133 was tuned for zram, where swapping is nearly free.)
    "vm.swappiness" = 100;

    # Wake kswapd at ~2% free RAM (~300MB) instead of the 0.1% default.
    "vm.watermark_scale_factor" = 200;

    # Bias toward keeping dentry/inode cache (nix-store lookups).
    "vm.vfs_cache_pressure" = 50;
  };

  # Layer 1: zswap (compressed pool in RAM) backed by a swapfile. The
  # swapfile sits inside the LUKS root, so it's encrypted at rest.
  zramSwap.enable = false;
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 16 * 1024; # MiB
    }
  ];
  # No zswap.zpool: kernel 7.x dropped the parameter (zsmalloc only).
  boot.kernelParams = [
    "zswap.enabled=1"
    "zswap.compressor=zstd"
    "zswap.max_pool_percent=25"
    "zswap.shrinker_enabled=Y"
  ];

  # Layer 3: systemd-oomd acts on cgroup PSI pressure before the kernel
  # OOM killer fires.
  systemd.oomd = {
    enable = true;
    enableRootSlice = true;
    enableUserSlices = true;
    enableSystemSlice = true;
    settings.OOM = {
      # Default 30s is too patient on an interactive laptop.
      DefaultMemoryPressureDurationSec = "10s";
      # Swap nearly exhausted means reclaim budget is gone. Only acts on
      # cgroups with ManagedOOMSwap=kill: nix-daemon (below) and
      # forgejo-runner.slice. The GNOME session is deliberately not opted in.
      SwapUsedLimit = "90%";
    };
  };
  systemd.services.nix-daemon.serviceConfig.ManagedOOMSwap = "kill";

  # Layers 2 + 4: cgroup ceilings + critical-service hardening. The CI
  # runner's own slice is configured next to the runner in default.nix.
  chrisportela.memory-protection = {
    enable = true;
    # Every CI nix build lands here (jobs share the host daemon socket).
    nixDaemon = {
      enable = true;
      memoryMax = "11G";
      memoryHigh = "9G";
    };
    microvmHost = true;
  };

  # Enable OpenGL
  hardware.graphics = {
    enable = true;
    #driSupport32Bit = true;
    extraPackages = with pkgs; [
      vpl-gpu-rt # for after 24.05
      # TODO: use unstable?
    ];
  };

  # Load nvidia driver for Xorg and Wayland
  # services.xserver.videoDrivers = [ "intel" ];

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  # networking.useDHCP = lib.mkDefault false;
  # networking.interfaces.enp6s0.useDHCP = lib.mkDefault true;
  # networking.interfaces.wlo1.useDHCP = lib.mkDefault true;

  services.thermald.enable = true;

  services.fwupd.enable = true;

  allowedUnfree = [
    "ipu6-camera-bins-unstable"
    "ipu6-camera-bins"
    "ivsc-firmware-unstable"
    "ivsc-firmware"
  ];

  hardware.ipu6.enable = false;
  hardware.ipu6.platform = "ipu6epmtl";

  nixpkgs.hostPlatform = "x86_64-linux";
  powerManagement.cpuFreqGovernor = "powersave";
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = config.hardware.enableRedistributableFirmware;
}
