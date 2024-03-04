{ lib, pkgs, ... }: with lib; {
  imports = [ ];

  config = {

    time.timeZone = mkDefault "Etc/UTC";
    time.hardwareClockInLocalTime = mkDefault true;

  };
}
