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
  credentials ? [ ],
  packages ? [ ],
  userName ? "cmp",
  uid ? 1000,
  gid ? 1000,
  authorizedKeys ? [ ],
  varSize ? 8192,
  extraShares ? [ ],
  sshHostKeyPath,
  homeManagerModule,
  claude ? false,
  claudeConfigDir ? null,
  direnv ? true,
  extraHomeModules ? [ ],
}:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  workspaceShares =
    lib.optionals (workspace != null) [
      {
        proto = "virtiofs";
        tag = "workspace";
        source = workspace;
        mountPoint = workspace;
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
      mountPoint = "/etc/ssh/host-keys";
    }
  ];

  claudeShares =
    lib.optionals (claude && claudeConfigDir != null) [
      {
        proto = "virtiofs";
        tag = "claude-config";
        source = claudeConfigDir;
        mountPoint = "/home/${userName}/.claude-host";
      }
    ];
in
{
  microvm = {
    inherit hypervisor vcpu mem;
    socket = "control.socket";

    interfaces = [
      {
        type = "tap";
        id = "vm-${hostName}";
        inherit mac;
      }
    ];

    writableStoreOverlay = "/nix/.rw-store";

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
      dns = [
        "8.8.8.8"
        "1.1.1.1"
      ];
    };
  };

  services.resolved.enable = true;

  services.openssh = {
    enable = true;
    hostKeys = [
      {
        path = "/etc/ssh/host-keys/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };

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

  environment.systemPackages = with pkgs; [
    git
    ripgrep
    curl
    fd
    jq
  ] ++ packages;

  imports = [ homeManagerModule ];

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;

  home-manager.users.${userName} = { pkgs, lib, ... }: {
    imports = extraHomeModules;

    programs.zsh.enable = true;

    programs.direnv = lib.mkIf direnv {
      enable = true;
      nix-direnv.enable = true;
    };

    home.activation.seedClaude = lib.mkIf claude (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -d "/home/${userName}/.claude" ] && [ -d "/home/${userName}/.claude-host" ]; then
          cp -a "/home/${userName}/.claude-host" "/home/${userName}/.claude"
        fi
      ''
    );

    home.stateVersion = "25.11";
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
