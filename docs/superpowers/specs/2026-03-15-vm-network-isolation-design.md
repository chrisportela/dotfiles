# VM Network Isolation Design

## Goal

Add layered network isolation to agent VMs so that restricted-mode VMs can only reach explicitly whitelisted destinations, with TLS interception for deep URL-level filtering on selected domains.

## Architecture

Two network modes, configured per-VM:

- **Default mode** — light hardening: local DNS via unbound, nftables forces DNS through unbound, blocks SMTP, allows all other egress.
- **Restricted mode** — defense-in-depth with three enforcement layers: DNS filtering (unbound), L7 proxy filtering (Squid with TLS interception), and L3/L4 firewall (nftables default-deny).

### Restricted mode data flow

```
workload
  → http_proxy=127.0.0.1:3128
  → Squid (CONNECT request reveals domain)
    → interceptDomains: ssl-bump → full URL visible → apply proxyBlockRegexes → allow/deny
    → allowedDomains: splice → pass through opaquely
    → anything else: terminate connection
  → nftables: only squid UID exits on 80/443
  → unbound: only resolves whitelisted domains
  → nftables: only unbound UID reaches upstream DNS on port 53
```

### Component matrix

| Component | Default mode | Restricted mode |
|-----------|-------------|-----------------|
| **unbound** | Forward all to upstream DNS | Refuse all; forward only whitelisted domains |
| **nftables** | Force DNS through unbound; block SMTP; accept all other egress | Default-deny output; only `unbound` UID → port 53; only `squid` UID → 80/443; drop everything else |
| **Squid** | Not running | ssl-bump `interceptDomains`; splice `allowedDomains`; deny rest |
| **CA cert** | Not present | Generated at `agent-vm create`; virtiofs mount; system trust store |
| **`http_proxy`/`https_proxy`** | Not set | Set globally → `127.0.0.1:3128` |
| **systemd-resolved** | Disabled | Disabled |

---

## Module interface

### New parameters for `vm-base.nix`

```nix
networkMode ? "default",       # "default" | "restricted"
allowedDomains ? [ ],          # Domains allowed through proxy (spliced, no TLS inspection)
interceptDomains ? [ ],        # Domains with TLS interception (full URL visibility)
proxyBlockRegexes ? [ ],       # URL regexes to block on intercepted traffic
allowSSH ? false,              # Allow outbound SSH (port 22) in restricted mode
upstreamDNS ? [ "1.1.1.1" "8.8.8.8" ],
```

### Auto-defaults for Claude VMs

When `claude = true && networkMode == "restricted"`, these are merged into the user-provided lists:

- `allowedDomains` += `api.anthropic.com`, `statsig.anthropic.com`, `sentry.io`
- `interceptDomains` += `api.github.com`

User-provided lists are additive, not replaced. Merging happens in `vm-network.nix`'s let block.

`upstreamDNS` is not exposed per-VM in `vmSubmodule` or `templateSubmodule` — all VMs use the `vm-base.nix` default (`[ "1.1.1.1" "8.8.8.8" ]`). Per-VM override can be added later if needed.

### Domain format conventions

User-supplied domains are plain names (e.g., `api.anthropic.com`). The implementation transforms them per-component:

- **Unbound forward-zones:** append trailing dot → `api.anthropic.com.`
- **Squid dstdomain ACLs:** prepend leading dot → `.api.anthropic.com` (matches domain + subdomains)

### Declarative VMs (`default.nix` vmSubmodule)

New options added to `vmSubmodule`: `networkMode` (str, default `"default"`), `allowedDomains` (listOf str), `interceptDomains` (listOf str), `proxyBlockRegexes` (listOf str), `allowSSH` (bool, default false).

These must be explicitly added to `mkVm`'s `inherit (vmCfg)` list (the existing function does not use a blanket inherit — each field is named):

```nix
inherit (vmCfg)
  ipAddress mac workspace packages credentials
  vcpu mem varSize extraShares copyWorkspace
  claude dotfiles direnv extraHomeModules
  networkMode allowedDomains interceptDomains
  proxyBlockRegexes allowSSH
  ;
```

### Templates (`default.nix` templateSubmodule)

All nullable so they only override when set: `networkMode` (nullOr str), `allowedDomains` (listOf str, default []), `interceptDomains` (listOf str, default []), `proxyBlockRegexes` (listOf str, default []), `allowSSH` (nullOr bool). Added to `cleanTemplate` serialization and `apply_template` in `agent-vm.nix`.

### CLI flags (`agent-vm create`)

- `--network-mode default|restricted`
- `--allowed-domains domain1,domain2,...`
- `--intercept-domains domain1,domain2,...`
- `--block-regex <regex>` (repeatable)
- `--allow-ssh`

These are parsed in `cmd_create`, serialized to Nix list expressions, and passed to the generated `flake.nix` template's `vm-base.nix` call.

---

## Component configurations

### Unbound — default mode

Standard forwarding with DNSSEC. Replaces systemd-resolved.

```nix
services.unbound = {
  enable = true;
  settings = {
    server = {
      interface = [ "127.0.0.1" "::1" ];
      access-control = [ "127.0.0.0/8 allow" "::1/128 allow" ];
      hide-identity = true;
      hide-version = true;
    };
    forward-zone = [{
      name = ".";
      forward-addr = [ "1.1.1.1@53" "8.8.8.8@53" ];
    }];
  };
};
```

### Unbound — restricted mode

Refuses all domains not explicitly forwarded. IPv6 listeners are omitted since restricted mode disables IPv6.

```nix
services.unbound = {
  enable = true;
  settings = {
    server = {
      interface = [ "127.0.0.1" ];
      access-control = [ "127.0.0.0/8 allow" ];
      hide-identity = true;
      hide-version = true;
      local-zone = [ "\".\" refuse" ];
    };
    # Generated: one forward-zone per domain in allowedDomains ++ interceptDomains
    forward-zone = [
      { name = "api.anthropic.com."; forward-addr = [ "1.1.1.1@53" "8.8.8.8@53" ]; }
      # ...
    ];
  };
};
```

### nftables — default mode

```
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
```

### nftables — restricted mode

The `upstream_dns` set is generated from the `upstreamDNS` config parameter.

```
table inet filter {
  set upstream_dns {
    type ipv4_addr
    elements = { ... }  # generated from upstreamDNS config
  }

  chain output {
    type filter hook output priority 0; policy drop;

    oif "lo" accept
    ct state established,related accept

    # ICMP — rate-limited to prevent tunneling
    ip protocol icmp icmp type { echo-request, echo-reply } limit rate 10/second accept
    ip protocol icmp icmp type { destination-unreachable, time-exceeded } accept

    # DNS — only unbound can reach upstream resolvers (IPv4)
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

    # SSH — only if allowSSH (conditionally included)
    # tcp dport 22 accept

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

    # ICMP — rate-limited (same as output)
    ip protocol icmp icmp type { echo-request, echo-reply } limit rate 10/second accept
    ip protocol icmp icmp type { destination-unreachable, time-exceeded } accept

    log prefix "nft-input-blocked: " counter drop
  }
}
```

**IPv6 note:** Restricted-mode VMs should disable IPv6 to prevent bypass via IPv6 DNS/egress:

```nix
networking.enableIPv6 = false;
```

This eliminates the need for IPv6-specific nftables rules. All IPv6 rules shown above are omitted when `enableIPv6 = false` (restricted mode). In default mode, IPv6 is left enabled and the IPv6 rules in the input chain apply.

### Squid — restricted mode

Generated as `squid.conf` via Nix string interpolation. The `security_file_certgen` path is `${pkgs.squid}/libexec/security_file_certgen` in the Nix expression.

```
http_port 127.0.0.1:3128 ssl-bump \
  cert=/etc/squid/ca/ca-cert.pem \
  key=/etc/squid/ca/ca-key.pem \
  generate-host-certificates=on \
  dynamic_cert_mem_cache_size=16MB

sslcrtd_program ${pkgs.squid}/libexec/security_file_certgen -s /var/lib/squid/certdb -M 16MB

acl localnet src 127.0.0.0/8 ::1
acl SSL_ports port 443
acl Safe_ports port 80 443
acl CONNECT method CONNECT

# Domain ACLs — generated from allowedDomains ++ interceptDomains (leading dot for subdomain match)
acl allowed_domains dstdomain .api.anthropic.com .statsig.anthropic.com .sentry.io
acl intercept_domains dstdomain .api.github.com

# URL blocking — generated from proxyBlockRegexes
# These ACLs apply AFTER ssl-bump decryption on bumped connections.
# Squid processes decrypted traffic as internal HTTP requests, so
# http_access rules see the full URL including path and method.
acl blocked_urls url_regex <generated patterns>

# SSL bump policy
acl step1 at_step SslBump1
acl step2 at_step SslBump2
ssl_bump peek step1 all
ssl_bump bump step2 intercept_domains
ssl_bump splice step2 allowed_domains
ssl_bump terminate step2 all

# Access control (evaluated for both CONNECT and bumped internal requests)
http_access deny !localnet
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
# blocked_urls only applies to intercept_domains — on spliced connections Squid only
# sees the CONNECT host:port, so a path-based regex would never match. Restricting
# to intercept_domains prevents accidental hostname matches blocking spliced traffic.
http_access deny blocked_urls intercept_domains
http_access allow allowed_domains
http_access allow intercept_domains
http_access deny all

# ICAP hook point (future — uncomment when adapter available)
# icap_enable on
# icap_service req_mod reqmod_precache icap://127.0.0.1:1344/request
# adaptation_access req_mod allow intercept_domains

cache deny all
access_log stdio:/var/log/squid/access.log
```

---

## CA certificate lifecycle

**Generation:** `agent-vm create` runs `openssl req -x509 -newkey rsa:4096 -nodes -keyout ca-key.pem -out ca-cert.pem -days 3650 -subj "/CN=agent-vm-<name> Proxy CA"` and stores both files in `$vm_dir/proxy-ca/`. This must happen after `mkdir -p "$vm_dir/proxy-ca/"` and before `chown -R microvm:kvm "$vm_dir"`.

**Mounting:** New virtiofs share in `vm-base.nix`, conditional on `networkMode == "restricted"`:

```nix
proxyCAShares = lib.optionals (networkMode == "restricted") [{
  proto = "virtiofs";
  tag = "proxy-ca";
  source = "${vmDir}/proxy-ca";  # vmDir is the VM's /var/lib/microvms/<name> directory
  mountPoint = "/etc/squid/ca";
}];
```

Added to `microvm.shares` alongside other conditional shares.

**Trust:** `security.pki.certificateFiles = [ "/etc/squid/ca/ca-cert.pem" ]` — all system TLS clients automatically trust certs signed by this CA.

**Squid cert DB:** `security_file_certgen` database at `/var/lib/squid/certdb` on persistent `/var`. Initialized on first boot by `vm-first-boot` service.

**Destruction:** `agent-vm destroy` removes the entire VM directory including the CA.

---

## Environment integration

### Proxy environment (restricted mode)

```nix
environment.sessionVariables = {
  http_proxy = "http://127.0.0.1:3128";
  https_proxy = "http://127.0.0.1:3128";
  HTTP_PROXY = "http://127.0.0.1:3128";
  HTTPS_PROXY = "http://127.0.0.1:3128";
  no_proxy = "localhost,127.0.0.1";
  NO_PROXY = "localhost,127.0.0.1";
};
```

### DNS (both modes)

```nix
services.resolved.enable = false;
networking.nameservers = [ "127.0.0.1" ];
```

Unbound is the sole resolver. This requires changes to existing `vm-base.nix`:

- **Remove** `services.resolved.enable = true;` (line 159)
- **Remove** `dns = [ "8.8.8.8" "1.1.1.1" ];` from `systemd.network.networks."10-lan"` (lines 152-155)
- **Remove** `systemd.services.systemd-resolved.serviceConfig.OOMScoreAdjust = -900;` (line 172) — resolved is disabled in both modes

**Important:** Removing the `dns` key from `systemd.network.networks."10-lan"` is mandatory, not just cleanup. If left in, networkd may race with the static `/etc/resolv.conf` generated from `networking.nameservers`, potentially overwriting it with external resolvers and bypassing unbound.

### Firewall deployment (both modes)

nftables rulesets are deployed via `networking.nftables`:

```nix
networking.firewall.enable = false;  # existing — keep disabled, we manage rules directly
networking.nftables.enable = true;
networking.nftables.ruleset = ''...'';  # mode-dependent ruleset
```

`networking.nftables` is independent of `networking.firewall` — they can coexist with firewall disabled. The nftables service starts before network interfaces via systemd ordering.

---

## First-boot extensions

The existing `vm-first-boot` service gains (restricted mode only):

1. Initialize Squid cert DB: `security_file_certgen -c -s /var/lib/squid/certdb -M 16MB`
2. Create `/var/log/squid/` with `squid:squid` ownership

**Systemd ordering:** The Squid service must not start until first-boot provisioning completes. Add:

```nix
systemd.services.squid = {
  after = [ "vm-first-boot.service" ];
  requires = [ "vm-first-boot.service" ];
};
```

---

## File organization

```
modules/nixos/agent-vms/
  ├── default.nix          # Host module (options, bridge, activation)
  ├── vm-base.nix          # Core VM config (microvm, users, packages, home-manager, OOM, persistence)
  ├── vm-network.nix       # NEW — Network isolation (unbound, nftables, squid, CA trust, proxy env)
  └── agent-vm.nix         # CLI tool derivation
```

`vm-network.nix` is a function taking network-related parameters, returning a NixOS module. Imported by `vm-base.nix`.

**Ad-hoc VM support:** `agent-vm.nix` currently embeds `vm-base.nix` content via `builtins.readFile ./vm-base.nix` and writes it into the VM directory. It must also embed and write `vm-network.nix` the same way, so that `import ./vm-network.nix` resolves correctly in ad-hoc VM flakes.

Import in `vm-base.nix`:

```nix
imports = [
  homeManagerModule
  ((import ./vm-network.nix) {
    inherit networkMode allowedDomains interceptDomains
            proxyBlockRegexes allowSSH upstreamDNS
            claude gatewayAddress;
  })
];
```

---

## Testing

From inside a restricted VM as the workload user:

```bash
# Should work
curl -I https://api.anthropic.com

# Should fail — domain not whitelisted
curl -I https://example.com

# Should fail — DNS refused
dig example.com

# Should fail — direct IP, nftables blocks non-squid egress
curl -I https://1.1.1.1

# Intercepted domain — URL-level filtering
curl https://api.github.com/repos/foo/bar/contents/README.md  # allowed
curl -X POST https://api.github.com/repos/foo/bar/actions/workflows/deploy.yml/dispatches  # blocked by regex

# Verify firewall is blocking
journalctl -k --grep="nft-blocked"
```

From inside a default VM:

```bash
# Should work — full egress
curl -I https://example.com

# Should fail — SMTP blocked
curl smtp://mail.example.com:25

# Should work — DNS resolves through unbound
dig example.com
```

---

## DNS bypass prevention

The three layers prevent all known bypass techniques:

| Bypass vector | Mitigation |
|---|---|
| Direct DNS to external resolvers | nftables: only `unbound` UID reaches port 53 |
| DNS-over-HTTPS (DoH) | nftables: only `squid` UID reaches 443; DoH endpoints not in whitelist |
| DNS-over-TLS (DoT) | nftables: port 853 blocked for all non-unbound |
| Hardcoded IP addresses | nftables: only `squid` UID exits on 80/443; direct connections dropped |
| DNS tunneling | unbound refuses non-whitelisted domains |
| Process impersonation | nftables `meta skuid` uses kernel socket UID tracking |
| IPv6 bypass | `networking.enableIPv6 = false` in restricted mode |
| ICMP tunneling | Rate-limited to 10/second for echo request/reply |
| Cross-VM SSH | Inbound SSH restricted to gateway IP in both modes |
| SSH tunnel (when `allowSSH=true`) | Accepted risk; opt-in flag, disabled by default |
