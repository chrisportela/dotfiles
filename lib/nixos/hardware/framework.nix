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
    # ../disko/zfs-impermanence.nix
    ../disko/luks-ext4.nix
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

  zramSwap = {
    enable = true;
    priority = 5;
    algorithm = "zstd";
    memoryPercent = 25;
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
