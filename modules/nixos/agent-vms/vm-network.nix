# vm-network.nix
# A function that takes network parameters and returns a NixOS module.
# Configures unbound (DNS), nftables (firewall), and optionally Squid (L7 proxy).
{
  networkMode ? "default",
  allowedDomains ? [ ],
  interceptDomains ? [ ],
  proxyBlockRegexes ? [ ],
  allowSSH ? false,
  upstreamDNS ? [
    "1.1.1.1"
    "8.8.8.8"
  ],
  claude ? false,
  gatewayAddress,
}:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  isRestricted = networkMode == "restricted";

  # Nix binary caches — needed for any restricted VM doing Nix builds
  nixCacheDomains = lib.optionals isRestricted [
    "cache.nixos.org"
    "nix-community.cachix.org"
    "chrisportela-dotfiles.cachix.org"
    # CDN backends (Fastly serves cache.nixos.org and cachix)
    "fastly.net"
  ];

  # Merge Claude auto-defaults when claude + restricted
  effectiveAllowedDomains = lib.unique (
    allowedDomains
    ++ nixCacheDomains
    ++ lib.optionals (claude && isRestricted) [
      # Anthropic
      "api.anthropic.com"
      "statsig.anthropic.com"
      "sentry.io"
      # Git
      "github.com"
      # npm
      "registry.npmjs.org"
      # pip
      "pypi.org"
      "files.pythonhosted.org"
      # cargo
      "crates.io"
      # CDN backends (CNAME targets for crates.io and pythonhosted.org)
      "fastly.net"
    ]
  );

  effectiveInterceptDomains = interceptDomains;

  allDomains = effectiveAllowedDomains ++ effectiveInterceptDomains;

  # Domain format transforms
  # Unbound forward-zones: append trailing dot
  unboundForwardZones = map (d: {
    name = "${d}.";
    forward-addr = map (dns: "${dns}@53") upstreamDNS;
  }) allDomains;

  # Squid dstdomain ACLs: prepend leading dot
  squidAllowedDomains = map (d: ".${d}") effectiveAllowedDomains;
  squidInterceptDomains = map (d: ".${d}") effectiveInterceptDomains;

  # nftables upstream DNS set elements
  upstreamDNSSet = lib.concatStringsSep ", " upstreamDNS;
in
{
  # --- DNS: unbound ---
  services.resolved.enable = false;
  networking.nameservers = [ "127.0.0.1" ];

  services.unbound = {
    enable = true;
    settings = {
      server = {
        interface =
          if isRestricted then
            [ "127.0.0.1" ]
          else
            [
              "127.0.0.1"
              "::1"
            ];
        access-control =
          if isRestricted then
            [ "127.0.0.0/8 allow" ]
          else
            [
              "127.0.0.0/8 allow"
              "::1/128 allow"
            ];
        hide-identity = true;
        hide-version = true;
      }
      // lib.optionalAttrs isRestricted {
        # Disable DNSSEC validation — the forwarder can't chase the delegation
        # chain when parent zones (com., .) are refused. We trust our explicit
        # upstream resolvers so this is safe.
        module-config = ''"iterator"'';
        # Refuse all DNS by default, then punch transparent holes for allowed domains.
        # local-zone is checked before forward-zone, so without transparent overrides
        # the root refuse would block everything — even domains with forward-zones.
        local-zone = [ "\".\" refuse" ] ++ map (d: "\"${d}.\" transparent") allDomains;
      };
      forward-zone =
        if isRestricted then
          unboundForwardZones
        else
          [
            {
              name = ".";
              forward-addr = map (dns: "${dns}@53") upstreamDNS;
            }
          ];
    };
  };

  # --- Firewall: nftables ---
  networking.nftables.enable = true;
  # Disable build-time ruleset validation — meta skuid references users
  # (unbound, squid) that only exist inside the VM, not on the build host.
  networking.nftables.checkRuleset = false;

  networking.nftables.ruleset =
    if isRestricted then
      ''
        table inet filter {
          set upstream_dns {
            type ipv4_addr
            elements = { ${upstreamDNSSet} }
          }

          chain output {
            type filter hook output priority 0; policy drop;

            oif "lo" accept
            ct state established,related accept

            # ICMP — rate-limited to prevent tunneling
            ip protocol icmp icmp type { echo-request, echo-reply } limit rate 10/second accept
            ip protocol icmp icmp type { destination-unreachable, time-exceeded } accept

            # DNS — only unbound can reach upstream resolvers
            ip daddr @upstream_dns meta skuid "unbound" udp dport 53 accept
            ip daddr @upstream_dns meta skuid "unbound" tcp dport 53 accept

            # Local DNS — all processes can query unbound (redundant with oif lo, kept for clarity)
            ip daddr 127.0.0.1 udp dport 53 accept
            ip daddr 127.0.0.1 tcp dport 53 accept

            # Block all other DNS (including DoT)
            udp dport 53 drop
            tcp dport 53 drop
            tcp dport 853 drop

            # HTTP/HTTPS — only squid
            meta skuid "squid" tcp dport { 80, 443 } accept

            ${lib.optionalString allowSSH ''
              # SSH — opt-in outbound
              tcp dport 22 accept
            ''}

            # Local proxy — all processes can reach squid (redundant with oif lo, kept for clarity)
            ip daddr 127.0.0.1 tcp dport 3128 accept

            log prefix "nft-blocked: " counter reject with icmp type admin-prohibited
          }

          chain input {
            type filter hook input priority 0; policy drop;
            iif "lo" accept
            ct state established,related accept

            # SSH — only from bridge gateway (host), not other VMs
            ip saddr ${gatewayAddress} tcp dport 22 accept

            # ICMP — rate-limited
            ip protocol icmp icmp type { echo-request, echo-reply } limit rate 10/second accept
            ip protocol icmp icmp type { destination-unreachable, time-exceeded } accept

            log prefix "nft-input-blocked: " counter drop
          }
        }
      ''
    else
      ''
        table inet filter {
          chain output {
            type filter hook output priority 0; policy accept;

            # Force DNS through local unbound (IPv4 + IPv6)
            ip daddr != 127.0.0.1 meta skuid != "unbound" udp dport 53 drop
            ip daddr != 127.0.0.1 meta skuid != "unbound" tcp dport 53 drop
            ip6 daddr != ::1 meta skuid != "unbound" udp dport 53 drop
            ip6 daddr != ::1 meta skuid != "unbound" tcp dport 53 drop
            tcp dport 853 meta skuid != "unbound" drop

            # Block outbound SMTP
            tcp dport { 25, 587 } log prefix "nft-smtp-blocked: " counter drop

            # Log unusual outbound
            tcp dport { 6667, 6697 } log prefix "nft-irc-out: " counter
          }

          chain input {
            type filter hook input priority 0; policy drop;
            iif "lo" accept
            ct state established,related accept

            # SSH — only from bridge gateway (host), not other VMs
            ip saddr ${gatewayAddress} tcp dport 22 accept

            # ICMP — rate-limited
            ip protocol icmp icmp type { echo-request, echo-reply } limit rate 10/second accept
            ip protocol icmp icmp type { destination-unreachable, time-exceeded } accept
            ip6 nexthdr icmpv6 icmpv6 type { echo-request, echo-reply } limit rate 10/second accept
            ip6 nexthdr icmpv6 icmpv6 type { destination-unreachable, time-exceeded } accept

            log prefix "nft-input-blocked: " counter drop
          }
        }
      '';

  # --- L7 Proxy: Squid with TLS interception (restricted mode only) ---
  # NixOS does not have a built-in services.squid module.
  # Configure manually via package + systemd service + config file.

  environment.systemPackages = lib.mkIf isRestricted [ pkgs.squid ];

  users.users.squid = lib.mkIf isRestricted {
    isSystemUser = true;
    group = "squid";
    home = "/var/lib/squid";
  };
  users.groups.squid = lib.mkIf isRestricted { };

  environment.etc."squid/squid.conf" = lib.mkIf isRestricted {
    text = ''
      http_port 127.0.0.1:3128 ssl-bump \
        cert=/var/lib/squid/ca/ca-cert.pem \
        key=/var/lib/squid/ca/ca-key.pem \
        generate-host-certificates=on \
        dynamic_cert_mem_cache_size=16MB

      pid_filename /run/squid/squid.pid

      sslcrtd_program ${pkgs.squid}/libexec/security_file_certgen -s /var/lib/squid/certdb -M 16MB

      acl localnet src 127.0.0.0/8 ::1
      acl SSL_ports port 443
      acl Safe_ports port 80 443
      acl CONNECT method CONNECT

      # Domain ACLs
      ${lib.optionalString (squidAllowedDomains != [ ]) ''
        acl allowed_domains dstdomain ${lib.concatStringsSep " " squidAllowedDomains}
      ''}
      ${lib.optionalString (squidInterceptDomains != [ ]) ''
        acl intercept_domains dstdomain ${lib.concatStringsSep " " squidInterceptDomains}
      ''}

      ${lib.optionalString (proxyBlockRegexes != [ ]) ''
        acl blocked_urls url_regex ${lib.concatStringsSep " " proxyBlockRegexes}
      ''}

      # SSL bump policy
      # Splice allowed domains immediately at step1 (no TLS inspection).
      # Only peek+bump intercept domains to read the full URL.
      acl step1 at_step SslBump1
      acl step2 at_step SslBump2
      ${lib.optionalString (squidAllowedDomains != [ ]) ''
        ssl_bump splice step1 allowed_domains
      ''}
      ${lib.optionalString (squidInterceptDomains != [ ]) ''
        ssl_bump peek step1 intercept_domains
        ssl_bump bump step2 intercept_domains
      ''}
      ssl_bump terminate step1 all

      # Access control
      http_access deny !localnet
      http_access deny !Safe_ports
      http_access deny CONNECT !SSL_ports
      ${lib.optionalString (proxyBlockRegexes != [ ] && squidInterceptDomains != [ ]) ''
        http_access deny blocked_urls intercept_domains
      ''}
      ${lib.optionalString (squidAllowedDomains != [ ]) ''
        http_access allow allowed_domains
      ''}
      ${lib.optionalString (squidInterceptDomains != [ ]) ''
        http_access allow intercept_domains
      ''}
      http_access deny all

      # ICAP hook point (future — uncomment when adapter available)
      # icap_enable on
      # icap_service req_mod reqmod_precache icap://127.0.0.1:1344/request
      # adaptation_access req_mod allow intercept_domains

      cache deny all
      access_log stdio:/var/log/squid/access.log
    '';
  };

  # Copy CA cert/key from virtiofs mount (root-owned, 0600) to a location
  # readable by the squid user, similar to ssh-host-keys-fixup in vm-base.nix.
  systemd.services.squid-ca-fixup = lib.mkIf isRestricted {
    description = "Copy proxy CA with correct permissions for Squid";
    wantedBy = [ "squid.service" ];
    before = [ "squid.service" ];
    after = [ "local-fs.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      mkdir -p /var/lib/squid/ca
      cp /etc/squid/ca/ca-cert.pem /var/lib/squid/ca/
      # Convert to traditional RSA format (Squid rejects PKCS#8 keys)
      ${pkgs.openssl}/bin/openssl rsa -traditional -in /etc/squid/ca/ca-key.pem -out /var/lib/squid/ca/ca-key.pem 2>/dev/null
      chown squid:squid /var/lib/squid/ca/ca-cert.pem /var/lib/squid/ca/ca-key.pem
      chmod 0600 /var/lib/squid/ca/ca-key.pem
      chmod 0644 /var/lib/squid/ca/ca-cert.pem
    '';
  };

  systemd.services.squid = lib.mkIf isRestricted {
    description = "Squid Web Proxy";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network.target"
      "vm-first-boot.service"
      "squid-ca-fixup.service"
    ];
    requires = [
      "vm-first-boot.service"
      "squid-ca-fixup.service"
    ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.squid}/bin/squid --foreground -f /etc/squid/squid.conf";
      ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
      User = "squid";
      Group = "squid";
      RuntimeDirectory = "squid";
      Restart = "on-failure";
    };
  };

  # --- CA trust (restricted mode) ---
  # The proxy CA cert lives on a virtiofs mount (/etc/squid/ca/) that is only
  # available at runtime, so we cannot use security.pki.certificateFiles (which
  # bakes certs into the Nix store at build time). Instead, create a combined
  # CA bundle at boot and point standard env vars at it.
  systemd.services.proxy-ca-trust = lib.mkIf isRestricted {
    description = "Create combined CA bundle with proxy CA";
    wantedBy = [ "multi-user.target" ];
    before = [ "squid.service" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mkdir -p /etc/ssl/certs
      cat ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt /etc/squid/ca/ca-cert.pem \
        > /etc/ssl/certs/ca-bundle-with-proxy.crt
    '';
  };

  # --- Proxy and CA environment variables (restricted mode) ---
  environment.sessionVariables = lib.mkIf isRestricted {
    http_proxy = "http://127.0.0.1:3128";
    https_proxy = "http://127.0.0.1:3128";
    HTTP_PROXY = "http://127.0.0.1:3128";
    HTTPS_PROXY = "http://127.0.0.1:3128";
    no_proxy = "localhost,127.0.0.1";
    NO_PROXY = "localhost,127.0.0.1";
    SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle-with-proxy.crt";
    NIX_SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle-with-proxy.crt";
    NODE_EXTRA_CA_CERTS = "/etc/squid/ca/ca-cert.pem";
  };

  # --- IPv6: disable in restricted mode ---
  networking.enableIPv6 = lib.mkIf isRestricted false;
}
