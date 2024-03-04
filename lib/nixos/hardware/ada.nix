{ config, lib, pkgs, modulesPath, ... }: {
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" "i2c-dev" ];
  boot.extraModulePackages = [ ];
  boot.supportedFilesystems = [ "ntfs" "ext4" "vfat" "zfs" ];
  boot.zfs = {
    extraPools = [ "spool" ];
    requestEncryptionCredentials = [
      "spool"
      "spool/docker"
      "spool/home"
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
      configurationLimit = 5;
      efiSupport = true;
      # efiInstallAsRemovable = true;
      devices = [ "nodev" ];
      timeoutStyle = "hidden";

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

    # Possible fix for discord crashing?
    nvidiaPersistenced = true;

    # Optionally, you may need to select the appropriate driver version for your specific GPU.
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault false;
  networking.interfaces.enp6s0.useDHCP = lib.mkDefault true;
  networking.interfaces.wlo1.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  powerManagement.cpuFreqGovernor = lib.mkDefault "schedutil";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
};
