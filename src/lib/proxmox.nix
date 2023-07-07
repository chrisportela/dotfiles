{
  mkContainer = { name, config, modulesPath, nixosGenerate, nixpkgs_overlay, system ? "x86_64-linux" }: nixosGenerate {
    inherit system;

    modules = [
      nixpkgs_overlay
      ({ lib, pkgs, modulesPath, ... }: {
        imports = [
          ./neovim.nix
        ];

        boot.kernelParams = [ "console=/dev/console" ];

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

        security.sudo = {
          enable = true;
          wheelNeedsPassword = false;
        };

        services.getty.autologinUser = lib.mkForce "admin";
        users.mutableUsers = lib.mkDefault false;
        users.allowNoPasswordLogin = lib.mkDefault true;
        users.defaultUserShell = lib.mkForce pkgs.zsh;

        programs.zsh.enable = true;

        users.users.admin = {
          isNormalUser = true;
          extraGroups = [ "wheel" ];
        };

        hardware.pulseaudio.enable = false;
        services.printing.enable = false;
        services.xserver.enable = false;
        sound.enable = false;

        system.stateVersion = "23.11";
      })
      config
    ];

    format = "proxmox-lxc";
  };
}
