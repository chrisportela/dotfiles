{
  pkgs,
  config,
  lib,
  modulesPath,
  ...
}:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot = {
    initrd.availableKernelModules = [ ];
    initrd.kernelModules = [ ];
    kernelModules = [ ];
    extraModulePackages = [ ];
    kernelParams = [
      "snd_bcm2835.enable_hdmi=1"
      "snd_bcm2835.enable_headphones=1"
      "vm.swappiness=50"
    ];

    loader.grub.enable = false;
    loader.generic-extlinux-compatible.enable = true;
  };

  swapDevices = [ ];
  zramSwap = {
    enable = true;
    priority = 5;
    algorithm = "zstd";
    memoryPercent = 50;
    # writebackDevice = "/dev/disk/by-label/zram-writeback";
  };

  networking = {
    hostName = "nixos";
    networkmanager.enable = true;
    # Prevent host becoming unreachable on wifi after some time.
    networkmanager.wifi.powersave = false;
  };

  # console.enable = false;
  environment.systemPackages = with pkgs; [
    libraspberrypi
    raspberrypi-eeprom
    # CEC
    # libcec
  ];

  # GPU Graphics
  # hardware.raspberry-pi."4".fkms-3d.enable = true;

  services.xserver = {
    enable = true;
    displayManager.lightdm.enable = true;
    desktopManager.gnome.enable = true;
    # desktopManager.xfce.enable = true;
    desktopManager.xterm.enable = true;
    # videoDrivers = [ "fbdev" ];
    resolutions = [
      {x = 1920; y = 1200; }
      {x = 1280; y = 1000; }
    ];
  };

  hardware.enableRedistributableFirmware = true;

  # Change permissions gpio devices (requires: gpio group)
  services.udev.extraRules = ''
    SUBSYSTEM=="bcm2835-gpiomem", KERNEL=="gpiomem", GROUP="gpio",MODE="0660"
    SUBSYSTEM=="gpio", KERNEL=="gpiochip*", ACTION=="add", RUN+="${pkgs.bash}/bin/bash -c 'chown root:gpio /sys/class/gpio/export /sys/class/gpio/unexport ; chmod 220 /sys/class/gpio/export /sys/class/gpio/unexport'"
    SUBSYSTEM=="gpio", KERNEL=="gpio*", ACTION=="add",RUN+="${pkgs.bash}/bin/bash -c 'chown root:gpio /sys%p/active_low /sys%p/direction /sys%p/edge /sys%p/value ; chmod 660 /sys%p/active_low /sys%p/direction /sys%p/edge /sys%p/value'"
  '';

  services.openssh = {
    enable = true;
    openFirewall = true;
  };

  security.sudo.wheelNeedsPassword = false;

  # Add user to group
  users = {
    groups.wheel = { };
    groups.gpio = { };
    groups.admin = { };

    users.admin = {
      isNormalUser = true;
      group = "admin";
      extraGroups = [
        "gpio"
        "wheel"
      ];
      initialPassword = "nimda"; # Need some kind of password to login
      openssh.authorizedKeys.keys = (import ../../sshKeys.nix).default;
    };
  };

  system.stateVersion = lib.mkDefault lib.trivial.version;
}
