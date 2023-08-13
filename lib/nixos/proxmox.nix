{
  mkPromoxVM = { name, config, inputs, pinned_nixpkgs, system ? "x86_64-linux" }: inputs.nixos-generators.nixosGenerate {
    inherit system;
    modules = [
      config
      pinned_nixpkgs
      ({ pkgs, config, modulesPath, ... }: {
        imports = [
          ./base-linux.nix
          (modulesPath + "/virtualisation/proxmox-image.nix")
        ];

        options.proxmox.virtio0 = "local-zfs:vm-9999-disk-0";

        config = {
          services.cloud-init.network.enable = true;

          services = {
            tailscale = {
              enable = true;
              package = pkgs.tailscale;
            };
          };

        };
      })
    ];
    format = "proxmox";
  };
  mkContainer = { name, config, inputs, pinned_nixpkgs, system ? "x86_64-linux" }: inputs.nixos-generators.nixosGenerate {
    inherit system;

    modules = [
      config
      pinned_nixpkgs
      ({ lib, pkgs, config, modulesPath, ... }: {
        imports = [ ];

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

        programs = {
          neovim = {
            enable = lib.mkDefault true;
            viAlias = lib.mkDefault true;
            vimAlias = lib.mkDefault true;
          };
          zsh.enable = true;
        };

        users = {
          mutableUsers = lib.mkDefault false;
          allowNoPasswordLogin = lib.mkDefault true;
          defaultUserShell = lib.mkForce pkgs.zsh;
          users.admin = {
            isNormalUser = true;
            extraGroups = [ "wheel" ];
          };
        };
        services.getty.autologinUser = lib.mkForce "admin";

        hardware.pulseaudio.enable = false;
        services.printing.enable = false;
        services.xserver.enable = false;
        sound.enable = false;

        system.stateVersion = "23.11";
      })
    ];

    format = "proxmox-lxc";
  };
}
