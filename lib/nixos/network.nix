{ config, lib, pkgs, ... }:
let
  cfg = config.chrisportela.network;
in
with lib; {
  options.chrisportela.network = {
    enable = mkEnableOption "network config";

    speedtest-utils = mkEnableOption "speedtest utilities";
    tailscale = mkEnableOption "Tailscale";
    mDNS = mkEnableOption "mDNS Publishing";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      inetutils
      ipcalc
      iperf3
      nftables
      tcpdump
      traceroute
    ] ++ optionals (cfg.speedtest-utils) [
      fast-cli
      ookla-speedtest
      speedtest-cli
    ];

    networking.nftables.enable = lib.mkDefault true;
    networking.nftables.checkRuleset = lib.mkDefault true;
    networking.firewall = {
      enable = true;
      allowedTCPPorts = optionals (config.services.openssh.enable) config.services.openssh.ports;
      allowedUDPPorts = optionals (cfg.tailscale) [ config.services.tailscale.port ];
      trustedInterfaces = optionals (cfg.tailscale) [ "tailscale0" ];
    };

    services.tailscale = mkIf cfg.tailscale {
      enable = true;
      package = pkgs.tailscale;
    };

    services.avahi = {
      enable = false;
      publish = {
        enable = true;
        addresses = true;
        workstation = true;
      };
    };

    services.resolved = {
      enable = true;
      fallbackDns = [ "127.0.0.1" ];
    };

    services.unbound = {
      enable = true;
      resolveLocalQueries = true;
      localControlSocketPath = "/run/unbound/unbount.ctl";
      enableRootTrustAnchor = true;
      settings.server.interface = [ "127.0.0.1" ];
    };
  };
}
