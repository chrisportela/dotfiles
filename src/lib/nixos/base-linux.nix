{ lib, config, pkgs, vscode-server, ... }: {
  imports = [ ./base.nix ];

  nix = {
    sshServe.keys = [ ];
    sshServe.enable = false;
    settings = {
      sandbox = lib.mkDefault true;
      trusted-users = [
        "root"
        "@wheel"
      ];
      # system-features = [ "big-parallel" "kvm" "recursive-nix" ];
      # extra-platforms = [ "aarch64-linux" "aarch64-darwin" ];
      # keep-outputs = true;
      # keep-derivations = true;
    };
  };

  nixpkgs.config.allowUnfree = true;

  boot.tmp.cleanOnBoot = true;
  zramSwap.enable = false;

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ ] ++ config.services.openssh.ports;
    allowedUDPPorts = [ config.services.tailscale.port ];
    trustedInterfaces = [ "tailscale0" ];
  };

  # time.timeZone = "America/New_York";

  i18n.defaultLocale = "en_US.UTF-8";
  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  # };

  services.xserver.enable = false;
  sound.enable = false;
  hardware.pulseaudio.enable = false;

  services = {
    avahi = {
      enable = false;
      publish = {
        enable = true;
        addresses = true;
        workstation = true;
      };
    };

    resolved = {
      enable = false;
      fallbackDns = [
        "1.1.1.1"
        "8.8.8.8"
      ];
    };

    openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
        KexAlgorithms = [
          "curve25519-sha256"
          "curve25519-sha256@libssh.org"
          "diffie-hellman-group-exchange-sha256"
          "ecdh-sha2-nistp256"
        ];
      };
      hostKeys = [
        {
          type = "rsa";
          bits = 4096;
          path = "/etc/ssh/ssh_host_rsa_key";
        }
        {
          type = "ed25519";
          path = "/etc/ssh/ssh_host_ed25519_key";
        }
        {
          type = "ecdsa";
          bits = 256;
          path = "/etc/ssh/ssh_host_ecdsa_key";
        }
      ];
      ports = [ 2222 ];
    };

    tailscale = {
      enable = true;
      package = pkgs.tailscale;
      useRoutingFeatures = "server";
    };

    vscode-server.enable = true;
  };

  environment.systemPackages = with pkgs; [ parted ];

  programs = {
    neovim = {
      enable = true;
      vimAlias = true;
      viAlias = true;
      defaultEditor = true;
    };

    tmux = {
      enable = true;
    };

    zsh = {
      enable = true;
      enableBashCompletion = true;
      enableCompletion = true;
    };
  };

  security.sudo.wheelNeedsPassword = false;

  users = {
    defaultUserShell = pkgs.zsh;

    groups.cmp = {};

    users = {
      cmp = {
        isNormalUser = true;
        group = "cmp";
        extraGroups = [ "wheel" ];
        packages = [ ];
        openssh.authorizedKeys.keys = (import ../sshKeys.nix).cmp;
      };
    };
  };

  system.stateVersion = lib.mkDefault "22.05";
}
