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
    /*
    networking.firewall.enable = lib.mkDefault false;
    networking.nftables.enable = lib.mkDefault true;
    networking.nftables.checkRuleset = lib.mkDefault true;
    networking.nftables.ruleset = lib.mkDefault ''
      table inet filter {
        chain input {
          iifname lo accept

          ct state {established, related} accept

          # ICMP
          # routers may also want: mld-listener-query, nd-router-solicit
          ip6 nexthdr icmpv6 icmpv6 type { destination-unreachable, packet-too-big, time-exceeded, parameter-problem, nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert } accept
          ip protocol icmp icmp type { destination-unreachable, router-advertisement, time-exceeded, parameter-problem } accept

          # allow "ping"
          ip6 nexthdr icmpv6 icmpv6 type echo-request accept
          ip protocol icmp icmp type echo-request accept

          # accept SSH connections (required for a server)
          tcp dport 22 accept

          tcp dport 80 accept
          tcp dport 443 accept
          tcp dport 8200 accept

          # count and drop any other traffic
          counter drop
        }

        # Allow all outgoing connections.
        chain output {
          type filter hook output priority 0;
          accept
        }

        chain forward {
          type filter hook forward priority 0;
          accept
        }
      }
    '';
    */
  };
}
