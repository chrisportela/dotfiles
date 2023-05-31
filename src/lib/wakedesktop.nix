# Provides wake desktop alias
{ pkgs, lib, ... }: rec {

  home.shellAliases = {
    wakedesktop = "${pkgs.wakeonlan}/bin/wakeonlan -i 10.38.0.255 D8:BB:C1:96:E5:01";
  };
}
