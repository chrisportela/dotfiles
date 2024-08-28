{ config, lib, pkgs, modulesPath, inputs, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    "${inputs.nixos-hardware}/framework/13-inch/common"
    "${inputs.nixos-hardware}/framework/13-inch/common/intel.nix"
    inputs.disko.nixosModules.disko
    # ../disko/zfs-impermanence.nix
    ../disko/luks-ext4.nix
  ];

  disko.devices.disk.root.device = "/dev/nvme0";

  # Need at least 6.9 to make suspend properly
  # Specifically this patch: https://github.com/torvalds/linux/commit/073237281a508ac80ec025872ad7de50cfb5a28a
  # boot.kernelPackages = lib.mkIf (lib.versionOlder pkgs.linux.version "6.9") (lib.mkDefault pkgs.linuxPackages_latest);

  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  # boot.kernelModules = [
  #   "kvm-intel"
  #   "i2c-dev"
  # ];
  boot.extraModulePackages = [ ];
  boot.supportedFilesystems = [ "ntfs" "ext4" "vfat" "zfs" ];
  boot.zfs = {
    extraPools = [ "zpool" ];
    requestEncryptionCredentials = [ "zpool" ];
    forceImportRoot = false;
  };
  # Because need latest kernel and it's not supported yet(?)
  # boot.zfs.package = pkgs.zfs_unstable;

  # Bootloader.
  boot.loader = {
    efi = {
      canTouchEfiVariables = true;
      efiSysMountPoint = "/boot";
    };

    systemd-boot.enable = true;
  };

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

  swapDevices = [{ device = "/dev/disk/by-uuid/bcf75db2-0312-4d27-958e-bb608604caf4"; }];

  zramSwap = {
    enable = true;
    priority = 5;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  # Enable OpenGL
  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;
    extraPackages = with pkgs; [
      # vpl-gpu-rt # for after 24.05
      onevpl-intel-gpu # deprecate after 24.05
      # TODO: use unstable?
    ];
  };

  # Load nvidia driver for Xorg and Wayland
  services.xserver.videoDrivers = [ "intel" ];

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  # networking.useDHCP = lib.mkDefault false;
  # networking.interfaces.enp6s0.useDHCP = lib.mkDefault true;
  # networking.interfaces.wlo1.useDHCP = lib.mkDefault true;

  services.thermald.enable = true;

  nixpkgs.hostPlatform = "x86_64-linux";
  powerManagement.cpuFreqGovernor = "powersave";
  hardware.cpu.intel.updateMicrocode = config.hardware.enableRedistributableFirmware;
}

