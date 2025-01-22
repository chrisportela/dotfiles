{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.chrisportela.network;
in
with lib;
{
  options.chrisportela.network = {
    enable = mkEnableOption "network config";

    speedtest-utils = mkEnableOption "speedtest utilities";
    tailscale = {
      enable = mkEnableOption "Tailscale";
      ssh = mkEnableOption "Tailscale SSH Access";
    };
    mDNS = mkEnableOption "mDNS Publishing with avahi";
  };

  config = mkIf cfg.enable {
    environment.systemPackages =
      with pkgs;
      [
        inetutils
        ipcalc
        iperf3
        nftables
        tcpdump
        traceroute
      ]
      ++ optionals (cfg.speedtest-utils) [
        fast-cli
        ookla-speedtest
        speedtest-cli
      ];

    networking.nftables.enable = lib.mkDefault true;
    networking.nftables.checkRuleset = lib.mkDefault true;
    networking.firewall = {
      enable = true;
      allowedTCPPorts = lib.optionals (config.services.openssh.enable) config.services.openssh.ports;
      allowedUDPPorts = lib.optionals (cfg.tailscale.enable) [
        config.services.tailscale.port
      ];
      trustedInterfaces = lib.optionals (cfg.tailscale.enable) [
        "tailscale0"
      ];
    };

    services.tailscale = lib.mkIf cfg.tailscale.enable {
      enable = true;
      package = pkgs.tailscale;
      extraUpFlags = lib.mkIf cfg.tailscale.ssh [ "--ssh" ];
    };

    services.avahi = lib.mkIf cfg.mDNS {
      enable = true;
      publish = {
        enable = true;
        addresses = true;
        workstation = true;
      };
    };

    services.resolved = {
      enable = true;
      fallbackDns = [
        "1.1.1.1#853" # Encrypted Cloudflare DNS
      ];
      dnssec = "false";
    };
  };
}
