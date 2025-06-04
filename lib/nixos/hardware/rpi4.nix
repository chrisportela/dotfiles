{
  pkgs,
  config,
  lib,
  ...
}:
{
  imports = [ ];

  console.enable = false;
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
  };

  # Enable audio devices
  boot.kernelParams = [
    "snd_bcm2835.enable_hdmi=1"
    "snd_bcm2835.enable_headphones=1"
  ];

  # Basic networking
  networking.networkmanager.enable = true;
  # Prevent host becoming unreachable on wifi after some time.
  networking.networkmanager.wifi.powersave = false;

  # Change permissions gpio devices (requires: gpio group)
  services.udev.extraRules = ''
    SUBSYSTEM=="bcm2835-gpiomem", KERNEL=="gpiomem", GROUP="gpio",MODE="0660"
    SUBSYSTEM=="gpio", KERNEL=="gpiochip*", ACTION=="add", RUN+="${pkgs.bash}/bin/bash -c 'chown root:gpio /sys/class/gpio/export /sys/class/gpio/unexport ; chmod 220 /sys/class/gpio/export /sys/class/gpio/unexport'"
    SUBSYSTEM=="gpio", KERNEL=="gpio*", ACTION=="add",RUN+="${pkgs.bash}/bin/bash -c 'chown root:gpio /sys%p/active_low /sys%p/direction /sys%p/edge /sys%p/value ; chmod 660 /sys%p/active_low /sys%p/direction /sys%p/edge /sys%p/value'"
  '';

  # Add user to group
  users = {
    groups.gpio = { };
    groups.admin = { };

    users.admin = {
      isNormalUser = true;
      group = "admin";
      extraGroups = [ "gpio" ];
      initialPassword = "nimda"; # Need some kind of password to login
      openssh.authorizedKeys.keys = (import ../../sshKeys.nix).default;
    };
  };

  system.stateVersion = lib.mkDefault lib.trivial.version;
}
