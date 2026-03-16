# VM Network Isolation Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add layered network isolation (unbound DNS + nftables + Squid TLS proxy) to agent VMs with two modes: default (light hardening) and restricted (defense-in-depth whitelist).

**Architecture:** New `vm-network.nix` module receives network parameters and returns a NixOS module configuring unbound, nftables, and optionally Squid. `vm-base.nix` imports it and gets cleaned up (remove resolved/dns). `default.nix` exposes the new options in vmSubmodule/templateSubmodule. `agent-vm.nix` gains CLI flags, CA generation, and embeds `vm-network.nix` for ad-hoc VMs.

**Tech Stack:** NixOS modules, nftables, unbound, Squid (ssl-bump), openssl

**Spec:** `docs/superpowers/specs/2026-03-15-vm-network-isolation-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `modules/nixos/agent-vms/vm-network.nix` | **Create** | Network isolation NixOS module (unbound, nftables, squid, proxy env, CA trust) |
| `modules/nixos/agent-vms/vm-base.nix` | **Modify** | Remove resolved/dns, import vm-network.nix, add proxy CA shares, extend first-boot |
| `modules/nixos/agent-vms/default.nix` | **Modify** | Add network options to vmSubmodule/templateSubmodule, pass through mkVm |
| `modules/nixos/agent-vms/agent-vm.nix` | **Modify** | Add CLI flags, CA generation, embed vm-network.nix, update templates/completions |

---

## Chunk 1: Core network module and vm-base integration

### Task 1: Create `vm-network.nix` — unbound and nftables (both modes)

This is the core new file. We build it incrementally — first unbound and nftables for both modes, then Squid in Task 2.

**Files:**
- Create: `modules/nixos/agent-vms/vm-network.nix`

- [ ] **Step 1: Create `vm-network.nix` with function signature and unbound config**

```nix
# vm-network.nix
# A function that takes network parameters and returns a NixOS module.
# Configures unbound (DNS), nftables (firewall), and optionally Squid (L7 proxy).
{
  networkMode ? "default",
  allowedDomains ? [ ],
  interceptDomains ? [ ],
  proxyBlockRegexes ? [ ],
  allowSSH ? false,
  upstreamDNS ? [ "1.1.1.1" "8.8.8.8" ],
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

  # Merge Claude auto-defaults when claude + restricted
  effectiveAllowedDomains = allowedDomains
    ++ lib.optionals (claude && isRestricted) [
      "api.anthropic.com"
      "statsig.anthropic.com"
      "sentry.io"
    ];

  effectiveInterceptDomains = interceptDomains
    ++ lib.optionals (claude && isRestricted) [
      "api.github.com"
    ];

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
        interface = if isRestricted then [ "127.0.0.1" ] else [ "127.0.0.1" "::1" ];
        access-control = if isRestricted
          then [ "127.0.0.0/8 allow" ]
          else [ "127.0.0.0/8 allow" "::1/128 allow" ];
        hide-identity = true;
        hide-version = true;
      } // lib.optionalAttrs isRestricted {
        local-zone = [ "\".\" refuse" ];
      };
      forward-zone = if isRestricted
        then unboundForwardZones
        else [{
          name = ".";
          forward-addr = map (dns: "${dns}@53") upstreamDNS;
        }];
    };
  };

  # --- Firewall: nftables ---
  networking.nftables.enable = true;

  networking.nftables.ruleset = if isRestricted then ''
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
  '' else ''
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

  # --- IPv6: disable in restricted mode ---
  networking.enableIPv6 = lib.mkIf isRestricted false;
}
```

- [ ] **Step 2: Verify the file parses**

Run: `cd /home/cmp/src/dotfiles && nix eval --expr 'let f = import ./modules/nixos/agent-vms/vm-network.nix; in builtins.typeOf f'`
Expected: `"lambda"`

- [ ] **Step 3: Commit**

```bash
git add modules/nixos/agent-vms/vm-network.nix
git commit -m "feat(agent-vms): create vm-network.nix with unbound and nftables"
```

---

### Task 2: Add Squid proxy configuration to `vm-network.nix`

**Files:**
- Modify: `modules/nixos/agent-vms/vm-network.nix`

- [ ] **Step 1: Add Squid service config (restricted mode only)**

NixOS does not have a built-in `services.squid` module. Configure Squid manually via package, systemd service, config file, and user/group.

Add to the module body (after the nftables section, before the IPv6 section):

```nix
  # --- L7 Proxy: Squid with TLS interception (restricted mode only) ---

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
        cert=/etc/squid/ca/ca-cert.pem \
        key=/etc/squid/ca/ca-key.pem \
        generate-host-certificates=on \
        dynamic_cert_mem_cache_size=16MB

      sslcrtd_program ${pkgs.squid}/libexec/security_file_certgen -s /var/lib/squid/certdb -M 16MB

      acl localnet src 127.0.0.0/8
      acl SSL_ports port 443
      acl Safe_ports port 80 443
      acl CONNECT method CONNECT

      # Domain ACLs
      acl allowed_domains dstdomain ${lib.concatStringsSep " " squidAllowedDomains}
      acl intercept_domains dstdomain ${lib.concatStringsSep " " squidInterceptDomains}

      ${lib.optionalString (proxyBlockRegexes != []) ''
      acl blocked_urls url_regex ${lib.concatStringsSep " " proxyBlockRegexes}
      ''}

      # SSL bump policy
      acl step1 at_step SslBump1
      acl step2 at_step SslBump2
      ssl_bump peek step1 all
      ssl_bump bump step2 intercept_domains
      ssl_bump splice step2 allowed_domains
      ssl_bump terminate step2 all

      # Access control
      http_access deny !localnet
      http_access deny !Safe_ports
      http_access deny CONNECT !SSL_ports
      ${lib.optionalString (proxyBlockRegexes != []) ''
      http_access deny blocked_urls intercept_domains
      ''}
      http_access allow allowed_domains
      http_access allow intercept_domains
      http_access deny all

      # ICAP hook point (future — uncomment when adapter available)
      # icap_enable on
      # icap_service req_mod reqmod_precache icap://127.0.0.1:1344/request
      # adaptation_access req_mod allow intercept_domains

      cache deny all
      access_log stdio:/var/log/squid/access.log
    '';
  };

  systemd.services.squid = lib.mkIf isRestricted {
    description = "Squid Web Proxy";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" "vm-first-boot.service" ];
    requires = [ "vm-first-boot.service" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.squid}/bin/squid --foreground -f /etc/squid/squid.conf";
      ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
      User = "squid";
      Group = "squid";
      Restart = "on-failure";
    };
  };

  # --- CA trust (restricted mode) ---
  security.pki.certificateFiles = lib.mkIf isRestricted [
    "/etc/squid/ca/ca-cert.pem"
  ];

  # --- Proxy environment variables (restricted mode) ---
  environment.sessionVariables = lib.mkIf isRestricted {
    http_proxy = "http://127.0.0.1:3128";
    https_proxy = "http://127.0.0.1:3128";
    HTTP_PROXY = "http://127.0.0.1:3128";
    HTTPS_PROXY = "http://127.0.0.1:3128";
    no_proxy = "localhost,127.0.0.1";
    NO_PROXY = "localhost,127.0.0.1";
  };
```

- [ ] **Step 2: Verify the file still parses**

Run: `cd /home/cmp/src/dotfiles && nix eval --expr 'let f = import ./modules/nixos/agent-vms/vm-network.nix; in builtins.typeOf f'`
Expected: `"lambda"`

- [ ] **Step 3: Commit**

```bash
git add modules/nixos/agent-vms/vm-network.nix
git commit -m "feat(agent-vms): add Squid TLS proxy config to vm-network.nix"
```

---

### Task 3: Modify `vm-base.nix` — remove resolved/dns, import vm-network.nix

**Files:**
- Modify: `modules/nixos/agent-vms/vm-base.nix:44-46,96-97,132-137,146-159,172,268-272,348-384`

**Note:** The `vm-base.nix` function signature already has the network parameters (`networkMode`, `allowedDomains`, `interceptDomains`, `proxyBlockRegexes`, `allowSSH`, `upstreamDNS`) in the working tree. Do NOT re-add them. This task only covers the body changes: proxyCAShares, removing resolved/dns/OOM, adding the vm-network.nix import, and extending first-boot.

- [ ] **Step 1: Add proxy CA shares to the let block**

In `vm-base.nix`, after the `dotfilesShares` definition (around line 95), add:

```nix
  proxyCAShares =
    lib.optionals (networkMode == "restricted") [
      {
        proto = "virtiofs";
        tag = "proxy-ca";
        source = "${sshHostKeyPath}/../proxy-ca";
        mountPoint = "/etc/squid/ca";
      }
    ];
```

**Note on path:** `sshHostKeyPath` is `/var/lib/microvms/<name>/ssh-host-keys`. Using `/../proxy-ca` navigates to the sibling `proxy-ca/` directory. This matches the VM directory structure. For declarative VMs, `sshHostKeyPath` is set in `mkVm` to `/var/lib/microvms/${name}/ssh-host-keys`, so `/../proxy-ca` resolves to `/var/lib/microvms/${name}/proxy-ca`.

- [ ] **Step 2: Add proxyCAShares to microvm.shares**

In the `microvm.shares` list (around line 123-137), add `++ proxyCAShares` to the concatenation:

Change:
```nix
      ++ dotfilesShares
      ++ extraShares;
```
To:
```nix
      ++ dotfilesShares
      ++ proxyCAShares
      ++ extraShares;
```

- [ ] **Step 3: Remove resolved and networkd dns config**

Remove these three items from `vm-base.nix`:

1. Remove `services.resolved.enable = true;` (line 159)
2. Remove the `dns` block from `systemd.network.networks."10-lan"` (lines 152-155):
   ```nix
      dns = [
        "8.8.8.8"
        "1.1.1.1"
      ];
   ```
3. Remove `systemd.services.systemd-resolved.serviceConfig.OOMScoreAdjust = -900;` (line 172)

- [ ] **Step 4: Add vm-network.nix to imports**

Change the `imports` line (line 272):
```nix
  imports = [ homeManagerModule ];
```
To:
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

- [ ] **Step 5: Extend vm-first-boot with Squid cert DB init (restricted mode only)**

In the `vm-first-boot` service script (around line 357-384), add a new script block in the `let`:

```nix
      squidInitScript = lib.optionalString (networkMode == "restricted") ''
        # Initialize Squid certificate database
        if [ ! -d /var/lib/squid/certdb ]; then
          mkdir -p /var/lib/squid
          ${pkgs.squid}/libexec/security_file_certgen -c -s /var/lib/squid/certdb -M 16MB
          chown -R squid:squid /var/lib/squid
        fi
        # Create Squid log directory
        mkdir -p /var/log/squid
        chown squid:squid /var/log/squid
      '';
```

And add `${squidInitScript}` to the script body before the sentinel touch:
```nix
    in ''
      ${copyWorkspaceScript}
      ${seedClaudeScript}
      ${squidInitScript}
      mkdir -p /var/lib
      touch /var/lib/vm-initialized
    '';
```

- [ ] **Step 6: Verify the module evaluates**

Run: `cd /home/cmp/src/dotfiles && nix eval .#nixosConfigurations.ada.config.microvm.vms --apply 'x: builtins.attrNames x'`

This checks that the NixOS config still evaluates. If there are no declarative VMs with network options, it should succeed without errors. If it fails, read the error and fix.

If no declarative VMs exist, alternatively test the import chain:
```bash
nix eval --expr 'let pkgs = import <nixpkgs> {}; in builtins.typeOf ((import ./modules/nixos/agent-vms/vm-network.nix) { gatewayAddress = "192.168.83.1"; })'
```
Expected: `"lambda"` (it returns a NixOS module function)

- [ ] **Step 7: Commit**

```bash
git add modules/nixos/agent-vms/vm-base.nix
git commit -m "feat(agent-vms): integrate vm-network.nix into vm-base.nix"
```

---

## Chunk 2: Host module options and CLI integration

### Task 4: Add network options to `default.nix` (vmSubmodule + templateSubmodule + mkVm)

**Files:**
- Modify: `modules/nixos/agent-vms/default.nix:14-67,82-158,161-191`

- [ ] **Step 1: Add network options to `templateSubmodule`**

In `templateSubmodule` (around line 14-67), add after the `copyWorkspace` option:

```nix
      networkMode = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Network mode: default or restricted";
      };
      allowedDomains = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Domains allowed through proxy (spliced)";
      };
      interceptDomains = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Domains with TLS interception";
      };
      proxyBlockRegexes = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "URL regexes to block on intercepted traffic";
      };
      allowSSH = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = "Allow outbound SSH in restricted mode";
      };
```

- [ ] **Step 2: Add network options to `vmSubmodule`**

In `vmSubmodule` (around line 82-158), add after `extraHomeModules`:

```nix
      networkMode = lib.mkOption {
        type = lib.types.str;
        default = "default";
        description = "Network mode: default or restricted";
      };
      allowedDomains = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Domains allowed through proxy (spliced)";
      };
      interceptDomains = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Domains with TLS interception";
      };
      proxyBlockRegexes = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "URL regexes to block on intercepted traffic";
      };
      allowSSH = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Allow outbound SSH in restricted mode";
      };
```

- [ ] **Step 3: Pass network options through `mkVm`**

In the `mkVm` function (around line 161-191), add the new fields to the `inherit (vmCfg)` block:

Change:
```nix
          inherit (vmCfg) copyWorkspace claude dotfiles direnv extraHomeModules;
```
To:
```nix
          inherit (vmCfg) copyWorkspace claude dotfiles direnv extraHomeModules
            networkMode allowedDomains interceptDomains proxyBlockRegexes allowSSH;
```

- [ ] **Step 4: Add network fields to `cleanTemplate` in agent-vm.nix import**

In `default.nix`, the `cleanTemplate` is in `agent-vm.nix`, not here. But we need to make sure templates data flows through. No changes needed in `default.nix` beyond the options — the template data is serialized in `agent-vm.nix`.

- [ ] **Step 5: Verify NixOS evaluation**

Run: `cd /home/cmp/src/dotfiles && nix eval .#nixosConfigurations.ada.config.system.build.toplevel.drvPath`
Expected: Outputs a `/nix/store/...` path without errors.

If this fails due to missing `proxy-ca/` directory for an existing declarative VM, the proxyCAShares in vm-base.nix should be gated on `networkMode == "restricted"` which means it won't activate for existing VMs using default mode.

- [ ] **Step 6: Commit**

```bash
git add modules/nixos/agent-vms/default.nix
git commit -m "feat(agent-vms): add network isolation options to vmSubmodule and templateSubmodule"
```

---

### Task 5: Update `agent-vm.nix` — CLI flags, CA generation, embed vm-network.nix

**Files:**
- Modify: `modules/nixos/agent-vms/agent-vm.nix:26,40-48,50-110,148-168,170-384,563-699`

This is the largest single task. It touches the CLI script, templates, completions, and CA generation.

- [ ] **Step 1: Embed `vm-network.nix` content**

Near line 26, after `vmBaseContent`:

```nix
  vmNetworkContent = builtins.readFile ./vm-network.nix;
```

- [ ] **Step 2: Add network fields to `cleanTemplate`**

In `cleanTemplate` (around line 40-46), add:

```nix
    inherit (t) workspace vcpu mem varSize claude dotfiles direnv copyWorkspace networkMode allowSSH;
    # ... existing packages/credentials ...
    allowedDomains = if t.allowedDomains != [ ] then t.allowedDomains else null;
    interceptDomains = if t.interceptDomains != [ ] then t.interceptDomains else null;
    proxyBlockRegexes = if t.proxyBlockRegexes != [ ] then t.proxyBlockRegexes else null;
```

- [ ] **Step 3: Add CLI flags to usage text and create flags**

In the `usage()` function (around line 76-109), add to the create flags section:

```
  --network-mode <mode>           Network mode: default or restricted
  --allowed-domains <d1,d2,...>   Domains allowed through proxy
  --intercept-domains <d1,d2,...> Domains with TLS interception
  --block-regex <regex>           URL regex to block (repeatable)
  --allow-ssh                     Allow outbound SSH in restricted mode
```

Add to bash completion `create_flags` (around line 571):
```
--network-mode --allowed-domains --intercept-domains --block-regex --allow-ssh
```

Add to zsh completion `_arguments` for create (around line 678-693):
```
'--network-mode[Network mode]:mode:(default restricted)' \
'--allowed-domains[Allowed domains]:domains:' \
'--intercept-domains[Intercept domains]:domains:' \
'*--block-regex[Block URL regex]:regex:' \
'--allow-ssh[Allow outbound SSH]' \
```

- [ ] **Step 4: Add network variables and flag parsing to `cmd_create`**

In `cmd_create` (around line 170-203), add local variables:

```bash
    local network_mode="default"
    local allowed_domains=""
    local intercept_domains=""
    local block_regexes=""
    local allow_ssh="false"
```

Add to the `while` case block:

```bash
        --network-mode) network_mode="$2"; shift 2 ;;
        --allowed-domains) allowed_domains="$2"; shift 2 ;;
        --intercept-domains) intercept_domains="$2"; shift 2 ;;
        --block-regex) block_regexes="$block_regexes $2"; shift 2 ;;
        --allow-ssh) allow_ssh="true"; shift ;;
```

- [ ] **Step 5: Add template application for network fields**

In `apply_template` (around line 148-168), add:

```bash
    val="$(echo "$tpl" | ${pkgs.jq}/bin/jq -r '.networkMode // empty')" && [ -n "$val" ] && network_mode="$val"
    val="$(echo "$tpl" | ${pkgs.jq}/bin/jq -r '.allowSSH // empty')" && [ -n "$val" ] && allow_ssh="$val"
    val="$(echo "$tpl" | ${pkgs.jq}/bin/jq -r '(.allowedDomains // []) | join(",")')" && [ -n "$val" ] && allowed_domains="$val"
    val="$(echo "$tpl" | ${pkgs.jq}/bin/jq -r '(.interceptDomains // []) | join(",")')" && [ -n "$val" ] && intercept_domains="$val"
    val="$(echo "$tpl" | ${pkgs.jq}/bin/jq -r '(.proxyBlockRegexes // []) | join(" ")')" && [ -n "$val" ] && block_regexes="$val"
```

- [ ] **Step 6: Build Nix list expressions for domains/regexes**

In `cmd_create`, after the existing `pkgs_nix` builder (around line 248), add:

```bash
    # Build allowedDomains Nix expression
    local allowed_nix="[ ]"
    if [ -n "$allowed_domains" ]; then
      allowed_nix="["
      IFS=',' read -ra dom_arr <<< "$allowed_domains"
      for d in "${dom_arr[@]}"; do
        allowed_nix="$allowed_nix \"$d\""
      done
      allowed_nix="$allowed_nix ]"
    fi

    # Build interceptDomains Nix expression
    local intercept_nix="[ ]"
    if [ -n "$intercept_domains" ]; then
      intercept_nix="["
      IFS=',' read -ra dom_arr <<< "$intercept_domains"
      for d in "${dom_arr[@]}"; do
        intercept_nix="$intercept_nix \"$d\""
      done
      intercept_nix="$intercept_nix ]"
    fi

    # Build proxyBlockRegexes Nix expression
    local regexes_nix="[ ]"
    if [ -n "$block_regexes" ]; then
      regexes_nix="["
      for r in $block_regexes; do
        regexes_nix="$regexes_nix \"$r\""
      done
      regexes_nix="$regexes_nix ]"
    fi
```

- [ ] **Step 7: Add CA generation to `cmd_create` (restricted mode only)**

After `ssh-keygen` and `.ip` file creation (around line 220), add:

```bash
    # Generate proxy CA for restricted mode
    if [ "$network_mode" = "restricted" ]; then
      sudo mkdir -p "$vm_dir/proxy-ca"
      sudo ${pkgs.openssl}/bin/openssl req -x509 -newkey rsa:4096 -nodes \
        -keyout "$vm_dir/proxy-ca/ca-key.pem" \
        -out "$vm_dir/proxy-ca/ca-cert.pem" \
        -days 3650 -subj "/CN=agent-vm-$name Proxy CA" 2>/dev/null
    fi
```

This must come before the `chown -R microvm:kvm "$vm_dir"` call (line 371).

- [ ] **Step 8: Copy `vm-network.nix` into VM directory**

After the existing `vm-base.nix` copy (around line 256-258), add:

```bash
    # Copy vm-network.nix into the VM directory
    sudo tee "$vm_dir/vm-network.nix" > /dev/null <<'VMNETWORK'
${vmNetworkContent}
VMNETWORK
```

- [ ] **Step 9: Add network parameters to generated `flake.nix`**

In the `flake.nix` template (around line 335-360), add after the `direnv` parameter:

```nix
          networkMode = "$network_mode";
          allowedDomains = $allowed_nix;
          interceptDomains = $intercept_nix;
          proxyBlockRegexes = $regexes_nix;
          allowSSH = $allow_ssh;
```

- [ ] **Step 10: Add `openssl` to script runtime dependencies**

The script already uses `pkgs.openssh`, `pkgs.jq`, etc. inline. The `openssl` call in step 7 uses `${pkgs.openssl}` which is already Nix-interpolated, so no additional PATH manipulation is needed.

- [ ] **Step 11: Run shellcheck**

Run: `cd /home/cmp/src/dotfiles && nix build .#nixosConfigurations.ada.config.environment.systemPackages --dry-run 2>&1 | head -5`

Then verify the script with:
```bash
# Extract the built script and run shellcheck
nix eval .#nixosConfigurations.ada.config.environment.systemPackages --apply 'pkgs: map (p: p.name) pkgs' 2>&1 | head -20
```

Or build the agent-vm derivation directly if possible. The key check is:
```bash
nix eval .#nixosConfigurations.ada.config.system.build.toplevel.drvPath
```
Expected: Outputs a store path without errors.

- [ ] **Step 12: Commit**

```bash
git add modules/nixos/agent-vms/agent-vm.nix
git commit -m "feat(agent-vms): add network isolation CLI flags and CA generation"
```

---

### Task 6: Verify full system evaluation

**Files:** None (verification only)

- [ ] **Step 1: Full NixOS evaluation**

Run: `cd /home/cmp/src/dotfiles && nix eval .#nixosConfigurations.ada.config.system.build.toplevel.drvPath`
Expected: Outputs a `/nix/store/...` path without errors.

- [ ] **Step 2: Shellcheck the built script**

Extract the agent-vm script from the built derivation and run shellcheck:
```bash
built=$(nix build .#nixosConfigurations.ada.config.environment.systemPackages --json 2>/dev/null | jq -r '.[0].outputs.out') || true
# If the above doesn't work for system packages, build the whole system:
nix eval .#nixosConfigurations.ada.config.system.build.toplevel.drvPath
```

The shellcheck is most easily verified by checking that `nix eval` succeeds — shell syntax errors in `writeShellScriptBin` cause build failures.

- [ ] **Step 3: Verify vm-network.nix is self-contained**

Ensure vm-network.nix can be imported standalone (simulating ad-hoc VM usage):
```bash
nix eval --expr '
  let
    f = import ./modules/nixos/agent-vms/vm-network.nix;
    mod = f { gatewayAddress = "192.168.83.1"; };
  in builtins.typeOf mod
'
```
Expected: `"lambda"` (returns a NixOS module function that takes `{ config, lib, pkgs, ... }`)

- [ ] **Step 4: Commit (if any fixes were needed)**

```bash
git add -A
git commit -m "fix(agent-vms): fix issues found during integration verification"
```

---

### Task 7: Test with a declarative VM definition (optional, if ada has VMs)

**Files:**
- Modify (optional): `hosts/nixos/ada/default.nix` (only for testing)

- [ ] **Step 1: Check if ada has declarative VMs**

Read `hosts/nixos/ada/default.nix` and look for `chrisportela.agent-vms.vms`.

- [ ] **Step 2: If VMs exist, add `networkMode = "default"` to one as a smoke test**

This verifies the option type is accepted. Don't change to "restricted" without proxy-ca setup.

- [ ] **Step 3: Evaluate**

Run: `nix eval .#nixosConfigurations.ada.config.system.build.toplevel.drvPath`

- [ ] **Step 4: Revert test change if it was just for verification**

```bash
git checkout -- hosts/nixos/ada/default.nix
```

---

### Task 8: Final commit of any remaining changes

- [ ] **Step 1: Check git status**

```bash
git status
git diff
```

- [ ] **Step 2: Stage and commit any uncommitted work**

```bash
git add modules/nixos/agent-vms/
git commit -m "feat(agent-vms): complete network isolation implementation"
```
