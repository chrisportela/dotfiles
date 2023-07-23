{ lib, config, pkgs, vscode-server, ... }: {
  imports = [];

  # boot.loader.systemd-boot.enable = true;
  # boot.loader.efi.canTouchEfiVariables = true;
  # boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  nix = {
    package = pkgs.nixVersions.nix_2_15;
    sshServe.keys = [ ];
    sshServe.enable = false;
    settings = {
      sandbox = lib.mkDefault true;
      trusted-users = [
        "root"
        # "builder"
        "cmp"
        "@wheel"
      ];
      experimental-features = [ "nix-command" "flakes" ];
      # system-features = [ "big-parallel" "kvm" "recursive-nix" ];
      # extra-platforms = [ "aarch64-linux" "aarch64-darwin" ];
      # keep-outputs = true;
      # keep-derivations = true;
    };
    distributedBuilds = true;
    buildMachines = [
      {
        systems = [ "x86_64-linux" "aarch64-linux" ];
        sshUser = "builder";
        maxJobs = 20;
        hostName = "nix.gorgon-basilisk.ts.net";
        speedFactor = 100;
        supportedFeatures = [ "kvm" "big-parallel" "nixos-test" "benchmark" ];
      }
    ];
    configureBuildUsers = true;
  };

  nixpkgs.config.allowUnfree = true;

  environment.pathsToLink = [
    "/share/nix-direnv"
  ];
  environment.systemPackages = with pkgs; [
    curl
    git
    htop
    neovim
    nixpkgs-fmt
    openssl_3
    parted
    tmux
    wget
  ];

  networking = {
    firewall = {
      enable = true;
      allowedTCPPorts = [ ] ++ config.services.openssh.ports;
      allowedUDPPorts = [ config.services.tailscale.port ];
      trustedInterfaces = [ "tailscale0" ];
    };
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
  };

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

  users = {
    defaultUserShell = pkgs.zsh;

    groups = { builder = { }; };

    users = {
      cmp = {
        isNormalUser = true;
        extraGroups = [ "wheel" ];
        packages = [ ];
        openssh.authorizedKeys.keys = (import ../sshKeys.nix).cmp;
      };

      builder = {
        isNormalUser = true;
        group = "users";
        shell = "/run/current-system/sw/bin/bash";
        openssh.authorizedKeys.keys = (import ../sshKeys.nix).builder;
      };
    };
  };

  system.stateVersion = "22.05";
}
/*
{ ... }: {
  nixpkgs.config.allowUnfree = true;

  nix = {
    package = pkgs.nixFlakes;
    settings = {
      trusted-users = [ "cmp" ];
      experimental-features = [ "nix-command" "flakes" ];

      trusted-public-keys = [
        "binarycache.cp-mba.local:xH/m5WHjOty8a0/n27WSKGhNC0eDf/HX6GREG+G6czM="
        "cache.cp-mba.local-1:YJIH05Ett5Tcq2eEyfroindEQdpwBG5F5f7ztZ+gFCw="
      ];
    };
  };

  boot.tmp.cleanOnBoot = true;
  zramSwap.enable = false;

  services.tailscale = {
    enable = true;
    package = pkgs.tailscale;
    useRoutingFeatures = "server";
  };
  services.vscode-server.enable = true;

  security.sudo.wheelNeedsPassword = false;
} */
