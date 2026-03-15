# vm-base.nix
# A function that takes VM parameters and returns a NixOS module.
# Used by both declarative VMs (from default.nix) and ad-hoc VM flakes.
{
  hostName,
  ipAddress,
  mac,
  gatewayAddress,
  vcpu ? 8,
  mem ? 4096,
  hypervisor ? "cloud-hypervisor",
  workspace ? null,
  copyWorkspace ? false,
  credentials ? [ ],
  packages ? [ ],
  userName ? "cmp",
  uid ? 1000,
  gid ? 1000,
  authorizedKeys ? [ ],
  varSize ? 51200,
  extraShares ? [ ],
  sshHostKeyPath,
  homeManagerModule,
  claude ? false,
  claudeConfigDir ? null,
  dotfiles ? false,
  dotfilesDir ? null,
  direnv ? true,
  extraHomeModules ? [ ],
  # Network isolation
  networkMode ? "default", # "default" | "restricted"
  allowedDomains ? [ ],    # Domains allowed through proxy (spliced — no TLS inspection)
  interceptDomains ? [ ],  # Domains with TLS interception (bumped — full URL visibility)
  proxyBlockRegexes ? [ ], # URL regexes to block on intercepted traffic
  allowSSH ? false,        # Allow outbound SSH (port 22) to whitelisted IPs
  upstreamDNS ? [ "1.1.1.1" "8.8.8.8" ],
}:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  workspaceMountPoint = if copyWorkspace then "${workspace}-ro" else workspace;

  workspaceShares =
    lib.optionals (workspace != null) [
      {
        proto = "virtiofs";
        tag = "workspace";
        source = workspace;
        mountPoint = workspaceMountPoint;
      }
    ];

  credentialShares = lib.imap0 (i: cred: {
    proto = "virtiofs";
    tag = "cred-${toString i}";
    source = cred.source;
    mountPoint = cred.mountPoint;
  }) credentials;

  sshKeyShares = [
    {
      proto = "virtiofs";
      tag = "ssh-host-keys";
      source = sshHostKeyPath;
      mountPoint = "/etc/ssh/host-keys-ro";
    }
  ];

  # Derive vsock CID from IP last octet (CIDs 0-2 are reserved, offset by 3)
  lastOctet = lib.toInt (lib.last (lib.splitString "." ipAddress));
  vsockCid = lastOctet + 3;

  claudeShares =
    lib.optionals (claude && claudeConfigDir != null) [
      {
        proto = "virtiofs";
        tag = "claude-config";
        source = claudeConfigDir;
        mountPoint = "/home/${userName}/.claude-host";
      }
    ];

  dotfilesShares =
    lib.optionals (dotfiles && dotfilesDir != null) [
      {
        proto = "virtiofs";
        tag = "dotfiles";
        source = dotfilesDir;
        mountPoint = dotfilesDir;
      }
    ];

  proxyCAShares =
    lib.optionals (networkMode == "restricted") [
      {
        proto = "virtiofs";
        tag = "proxy-ca";
        source = "${sshHostKeyPath}/../proxy-ca";
        mountPoint = "/etc/squid/ca";
      }
    ];
in
{
  microvm = {
    inherit hypervisor vcpu mem;
    socket = "control.socket";
    vsock.cid = vsockCid;

    interfaces = [
      {
        type = "tap";
        id = "vm-${hostName}";
        inherit mac;
      }
    ];

    # Place writable nix store overlay on persistent /var so installed
    # packages survive reboots (default /nix/.rw-store is on tmpfs)
    writableStoreOverlay = "/var/nix-store-overlay";

    volumes = [
      {
        mountPoint = "/var";
        image = "var.img";
        size = varSize;
      }
    ];

    shares =
      [
        {
          proto = "virtiofs";
          tag = "ro-store";
          source = "/nix/store";
          mountPoint = "/nix/.ro-store";
        }
      ]
      ++ sshKeyShares
      ++ workspaceShares
      ++ credentialShares
      ++ claudeShares
      ++ dotfilesShares
      ++ proxyCAShares
      ++ extraShares;
  };

  networking = {
    hostName = hostName;
    firewall.enable = false;
    useNetworkd = true;
  };

  systemd.network = {
    enable = true;
    networks."10-lan" = {
      matchConfig.Name = "e*";
      addresses = [ { Address = "${ipAddress}/24"; } ];
      routes = [ { Gateway = gatewayAddress; } ];
};
  };

  # --- OOM protection ---
  # Enable systemd-oomd for proactive cgroup-pressure-based OOM handling.
  # Kills workloads under memory pressure before the kernel OOM killer
  # fires indiscriminately.
  systemd.oomd = {
    enable = true;
    enableRootSlice = true;
    enableUserSlices = true;
  };

  # Protect core system services from OOM (-900 = almost never killed)
  systemd.services.systemd-networkd.serviceConfig.OOMScoreAdjust = -900;
  systemd.services.nix-daemon.serviceConfig.OOMScoreAdjust = -800;

  # Make user sessions more likely to be killed under memory pressure.
  # systemd-oomd monitors this slice and kills within it at 80% pressure.
  systemd.slices."user-".sliceConfig = {
    ManagedOOMMemoryPressure = "kill";
    ManagedOOMMemoryPressureLimit = "80%";
  };

  # Copy SSH host keys from virtiofs mount (root:kvm 0640) to local dir with
  # correct permissions (root:root 0600) before sshd starts
  systemd.services.ssh-host-keys-fixup = {
    description = "Copy SSH host keys with correct permissions";
    wantedBy = [ "sshd.service" ];
    before = [ "sshd.service" ];
    serviceConfig.Type = "oneshot";
    script = ''
      mkdir -p /etc/ssh/host-keys
      cp /etc/ssh/host-keys-ro/ssh_host_ed25519_key /etc/ssh/host-keys/
      cp /etc/ssh/host-keys-ro/ssh_host_ed25519_key.pub /etc/ssh/host-keys/
      chmod 0600 /etc/ssh/host-keys/ssh_host_ed25519_key
      chmod 0644 /etc/ssh/host-keys/ssh_host_ed25519_key.pub
      chown root:root /etc/ssh/host-keys/ssh_host_ed25519_key /etc/ssh/host-keys/ssh_host_ed25519_key.pub
    '';
  };

  services.openssh = {
    enable = true;
    hostKeys = [
      {
        path = "/etc/ssh/host-keys/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };
  systemd.services.sshd.serviceConfig.OOMScoreAdjust = lib.mkForce (-900);

  users.groups.${userName} = {
    inherit gid;
  };

  users.users.${userName} = {
    isNormalUser = true;
    inherit uid;
    group = userName;
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = authorizedKeys;
  };

  security.sudo.wheelNeedsPassword = false;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  programs.zsh.enable = true;
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };
  programs.tmux.enable = true;

  nixpkgs.config.allowUnfree = claude;

  environment.systemPackages = with pkgs; [
    git
    tmux
    neovim
    nodejs
    python3
    ripgrep
    curl
    fd
    jq
    bash
  ] ++ lib.optionals claude [ pkgs.claude-code ] ++ packages;

  # Ensure /bin/bash exists for scripts that expect it
  system.activationScripts.binbash = lib.stringAfter [ "stdio" ] ''
    mkdir -p /bin
    ln -sf ${pkgs.bash}/bin/bash /bin/bash
  '';

  # Persist /home/${userName} on the /var volume so user data survives reboots.
  # The tmpfs rootfs is ephemeral — without this, home is wiped on every start.
  fileSystems."/home/${userName}" = {
    device = "/var/home/${userName}";
    fsType = "none";
    options = [ "bind" ];
  };

  # Ensure the backing directory exists with correct ownership before the
  # bind mount is attempted
  systemd.tmpfiles.rules = [
    "d /var/home/${userName} 0700 ${userName} ${userName} -"
  ];

  imports = [
    homeManagerModule
    ((import ./vm-network.nix) {
      inherit networkMode allowedDomains interceptDomains
              proxyBlockRegexes allowSSH upstreamDNS
              claude gatewayAddress;
    })
  ];

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;

  home-manager.users.${userName} = { pkgs, lib, ... }: {
    imports = extraHomeModules;

    programs.zsh.enable = true;

    programs.tmux = {
      enable = true;
      terminal = "tmux-256color";
      escapeTime = 0;
      historyLimit = 50000;
      mouse = true;
      keyMode = "vi";
      baseIndex = 1;
      extraConfig = ''
        set -g renumber-windows on
        set -g set-titles on
        set -g focus-events on
        bind | split-window -h -c "#{pane_current_path}"
        bind - split-window -v -c "#{pane_current_path}"
        bind c new-window -c "#{pane_current_path}"
      '';
    };

    programs.git = {
      enable = true;
      userName = userName;
      userEmail = "${userName}@${hostName}";
      extraConfig = {
        init.defaultBranch = "main";
        pull.rebase = true;
      };
    };

    programs.neovim = {
      enable = true;
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;
      extraLuaConfig = ''
        vim.opt.number = true
        vim.opt.relativenumber = true
        vim.opt.expandtab = true
        vim.opt.shiftwidth = 2
        vim.opt.tabstop = 2
        vim.opt.smartindent = true
        vim.opt.termguicolors = true
        vim.opt.signcolumn = "yes"
        vim.opt.clipboard = "unnamedplus"
        vim.opt.undofile = true
        vim.opt.ignorecase = true
        vim.opt.smartcase = true
        vim.opt.scrolloff = 8
        vim.g.mapleader = " "
      '';
    };

    programs.direnv = lib.mkIf direnv {
      enable = true;
      nix-direnv.enable = true;
    };

    home.stateVersion = "25.11";
  };

  # --- First-boot provisioning ---
  # All one-time setup (workspace copy, credential seeding) is gated behind
  # a sentinel file on the persistent /var volume. This means:
  #   - start/stop preserves all VM state (var.img persists)
  #   - only `agent-vm destroy` removes the disk and resets state
  #   - subsequent boots skip provisioning entirely

  systemd.services.vm-first-boot = {
    description = "First-boot provisioning";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    unitConfig.ConditionPathExists = "!/var/lib/vm-initialized";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = let
      copyWorkspaceScript = lib.optionalString (workspace != null && copyWorkspace) ''
        # Copy workspace from RO virtiofs mount to writable location
        if [ -d "${workspaceMountPoint}" ]; then
          echo "Copying workspace to ${workspace}..."
          ${pkgs.sudo}/bin/sudo -u ${userName} ${pkgs.rsync}/bin/rsync -a "${workspaceMountPoint}/" "${workspace}/"
        fi
      '';
      seedClaudeScript = lib.optionalString claude ''
        home="/home/${userName}"
        # Seed .claude/ directory from host mount
        if [ ! -d "$home/.claude" ] && [ -d "$home/.claude-host" ]; then
          ${pkgs.sudo}/bin/sudo -u ${userName} cp -a "$home/.claude-host" "$home/.claude"
        fi
        # Seed .claude.json from latest backup
        if [ ! -f "$home/.claude.json" ] && [ -d "$home/.claude-host/backups" ]; then
          latest="$(ls -t "$home/.claude-host/backups/.claude.json."* 2>/dev/null | head -1)"
          if [ -n "$latest" ]; then
            ${pkgs.sudo}/bin/sudo -u ${userName} cp "$latest" "$home/.claude.json"
          fi
        fi
      '';
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
    in ''
      ${copyWorkspaceScript}
      ${seedClaudeScript}
      ${squidInitScript}
      mkdir -p /var/lib
      touch /var/lib/vm-initialized
    '';
  };

  # Fast shutdown
  systemd.settings.Manager = {
    DefaultTimeoutStopSec = "5s";
  };

  # Fix nix store mount deadlock on shutdown (microvm.nix issue #170)
  systemd.mounts = [
    {
      what = "store";
      where = "/nix/store";
      overrideStrategy = "asDropin";
      unitConfig.DefaultDependencies = false;
    }
  ];

  system.stateVersion = "25.11";
}
