let
  ipv4_ips = [
    # https://www.cloudflare.com/ips-v4
    # 2024-03-04
    "103.21.244.0/22"
    "103.22.200.0/22"
    "103.31.4.0/22"
    "104.16.0.0/13"
    "104.24.0.0/14"
    "108.162.192.0/18"
    "131.0.72.0/22"
    "141.101.64.0/18"
    "162.158.0.0/15"
    "172.64.0.0/13"
    "173.245.48.0/20"
    "188.114.96.0/20"
    "190.93.240.0/20"
    "197.234.240.0/22"
    "198.41.128.0/17"
  ];
  ipv6_ips = [
    # https://www.cloudflare.com/ips-v6
    # 2024-03-04
    "2400:cb00::/32"
    "2606:4700::/32"
    "2803:f800::/32"
    "2405:b500::/32"
    "2405:8100::/32"
    "2a06:98c0::/29"
    "2c0f:f248::/32"
  ];
in
{ lib, config, ... }:
let
  cfg = config.services.nginx;
in
with lib;
{
  options = {
    services.nginx = {
      allowCloudflareProxyIPs = mkOption {
        default = false;
        type = types.bool;
        description = ''
          Enable router features and configuration
        '';
      };
      cloudflareIPv4IPs = mkOption {
        default = ipv4_ips;
        type = with types; listOf string;
        description = ''
          List of Cloudflare IPv4 blocks from https://www.cloudflare.com/ips-v4
        '';
      };
      cloudflareIPv6IPs = mkOption {
        default = ipv6_ips;
        type = with types; listOf string;
        description = ''
          List of Cloudflare IPv6 blocks from https://www.cloudflare.com/ips-v6
        '';
      };
    };
  };

  config = mkIf cfg.allowCloudflareProxyIPs {
    services.nginx.appendHttpConfig = ''
      # Cloudflare IPv4 Addresses
      ${lib.concatMapStringsSep "\n" (x: "set_real_ip_from ${x};") (cfg.cloudflareIPv4IPs)}

      # Cloudflare IPv6 Addresses
      ${lib.concatMapStringsSep "\n" (x: "set_real_ip_from ${x};") (cfg.cloudflareIPv6IPs)}

      # Tell nginx to use CF's header to get the real IP
      real_ip_header CF-Connecting-IP;
      real_ip_recursive on;
    '';
  };
}
