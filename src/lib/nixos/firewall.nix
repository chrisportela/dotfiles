{ config, lib, pkgs, ... }:
let
  cfg = config.services.router;
in
with lib;
{

  options = {
    # services.firewall = {
    #   enable = mkOption {
    #     default = false;
    #     type = with types; bool;
    #     description = ''
    #       Enable router features and configuration
    #     '';
    #   };
    # };
  };

  config = {
    environment.systemPackages = with pkgs; [
      inetutils
      ipcalc
      iperf3
      nftables
      tcpdump
      traceroute
    ];

    networking.firewall = {
      enable = true;
      allowedTCPPorts = optionals (config.services.openssh.enable) config.services.openssh.ports;
      allowedUDPPorts = optionals (config.services.tailscale.enable) [ config.services.tailscale.port ];
      trustedInterfaces = optionals (config.services.tailscale.enable) [ "tailscale0" ];
    };
  };
}
