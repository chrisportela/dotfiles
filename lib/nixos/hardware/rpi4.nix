{ nixos-hardware }:
{
  pkgs,
  config,
  lib,
  ...
}:
{
  imports = [
    # "${nixos-hardware}/raspberry-pi/4"
  ];

  # nixpkgs.overlays = [
  #   (self: super: { libcec = super.libcec.override { withLibraspberrypi = true; }; })
  # ];

  # hardware = {
  #   # raspberry-pi."4".apply-overlays-dtmerge.enable = true;
  #   deviceTree = {
  #     enable = true;
  #     filter = "*rpi-4-*.dtb";
  #   };
  # };

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
  # boot.loader.raspberryPi.firmwareConfig = ''
  #   dtparam=audio=on
  # '';

  # Basic networking
  networking.networkmanager.enable = true;
  # Prevent host becoming unreachable on wifi after some time.
  networking.networkmanager.wifi.powersave = false;

  # Create gpio group
  # users.groups.gpio = { };

  # Change permissions gpio devices
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
    };
  };

  # SPI
  # hardware.raspberry-pi."4".apply-overlays-dtmerge.enable = true;
  hardware.deviceTree = {
    # enable = true;
    # filter = "*-rpi-*.dtb";
    # overlays = [
    #   {
    #     name = "spi";
    #     dtsoFile = ./spi0-0cd.dtso;
    #   }
    # ];
  };

  users.groups.spi = { };

  # services.udev.extraRules = ''
  #   SUBSYSTEM=="spidev", KERNEL=="spidev0.0", GROUP="spi", MODE="0660"
  # '';

  # services.udev.extraRules = ''
  #   # allow access to raspi cec device for video group (and optionally register it as a systemd device, used below)
  #   KERNEL=="vchiq", GROUP="video", MODE="0660", TAG+="systemd", ENV{SYSTEMD_ALIAS}="/dev/vchiq"
  # '';

  # optional: attach a persisted cec-client to `/run/cec.fifo`, to avoid the CEC ~1s startup delay per command
  # scan for devices: `echo 'scan' > /run/cec.fifo ; journalctl -u cec-client.service`
  # set pi as active source: `echo 'as' > /run/cec.fifo`
  # systemd.sockets."cec-client" = {
  #   after = [ "dev-vchiq.device" ];
  #   bindsTo = [ "dev-vchiq.device" ];
  #   wantedBy = [ "sockets.target" ];
  #   socketConfig = {
  #     ListenFIFO = "/run/cec.fifo";
  #     SocketGroup = "video";
  #     SocketMode = "0660";
  #   };
  # };
  # systemd.services."cec-client" = {
  #   after = [ "dev-vchiq.device" ];
  #   bindsTo = [ "dev-vchiq.device" ];
  #   wantedBy = [ "multi-user.target" ];
  #   serviceConfig = {
  #     ExecStart = ''${pkgs.libcec}/bin/cec-client -d 1'';
  #     ExecStop = ''/bin/sh -c "echo q > /run/cec.fifo"'';
  #     StandardInput = "socket";
  #     StandardOutput = "journal";
  #     Restart = "no";
  #   };
  # };

  system.stateVersion = lib.mkDefault "25.05";
}
