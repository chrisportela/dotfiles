{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.chrisportela.stats;
in
{
  options.chrisportela.stats = {
    enable = lib.mkEnableOption "Stats menu bar app";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.stats
    ];
  };
}
