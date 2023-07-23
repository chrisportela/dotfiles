let
  ipv4_ips = [
    # https://www.cloudflare.com/ips-v4
    # 2023-07-21
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
    # 2023-07-21
    "2400:cb00::/32"
    "2405:8100::/32"
    "2405:b500::/32"
    "2606:4700::/32"
    "2803:f800::/32"
    "2a06:98c0::/29"
    "2c0f:f248::/32"
  ];
in
{ ... }: {
  services.nginx.appendHttpConfig = ''
    ${lib.concatMapStringsSep "\n" (x: "set_real_ip_from ${x};") (ipv4_ips)}

    ${lib.concatMapStringsSep "\n" (x: "set_real_ip_from ${x};") (ipv6_ips)}

    real_ip_header CF-Connecting-IP;
    real_ip_recursive on;
  '';
}
