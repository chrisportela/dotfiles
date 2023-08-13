{ config, lib, pkgs, ... }:
let
  cfg = config.services.router;
in
with lib;
{

  options = {
    services.router = {
      enable = mkOption {
        default = false;
        type = with types; bool;
        description = ''
          Enable router features and configuration
        '';
      };

      # user = mkOption {
      #   default = "username";
      #   type = with types; uniq string;
      #   description = ''
      #     Name of the user.
      #   '';
      # };
    };
  };

  config = mkIf cfg.services.router.enable {

    environment.systemPackages = with pkgs; [
      inetutils
      ipcalc
      iperf3
      nftables
      tcpdump
      traceroute
      fast-cli
      ookla-speedtest
      speedtest-cli
    ];

    networking.firewall = {
      enable = true;
      allowedTCPPorts = optionals (config.services.openssh.enable) config.services.openssh.ports;
      allowedUDPPorts = optionals (config.services.tailscale.enable) [ config.services.tailscale.port ];
      trustedInterfaces = optionals (config.services.tailscale.enable) [ "tailscale0" ];
    };
  };

}
