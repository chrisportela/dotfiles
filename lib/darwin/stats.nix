{lib, pkgs, config, ...}:
let
  cfg = config.chrisportela;
in
{
  options.chrisportela = {
    enableStatsApp = lib.mkEnableOption "Stats menu bar app";
  };

  # TODO: [maybe] add and check cfg.enable
  config = lib.mkIf cfg.enableStatsApp {
    environment.systemPackages = [
      pkgs.stats
    ];
  };
}
