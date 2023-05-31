({ config, pkgs, ... }: {
  imports = [ ./hardware-configuration.nix ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  nix = {
    package = pkgs.nixVersions.nix_2_14;
    sshServe.keys = [ ];
    sshServe.enable = false;
    settings = {
      sandbox = true;
      trusted-users = [ "root" "builder" "@wheel" ];
      experimental-features = [ "nix-command" "flakes" ];
      system-features = [ "big-parallel" "kvm" "recursive-nix" ];
      extra-platforms = [ "aarch64-linux" "aarch64-darwin" ];
      keep-outputs = true;
      keep-derivations = true;
    };
  };

  nixpkgs.config.allowUnfree = true;

  environment.pathsToLink = [
    "/share/nix-direnv"
  ];
  environment.systemPackages = with pkgs; [
    curl
    neovim
    wget
    htop
    tmux
    nixpkgs-fmt
    git
    parted
    openssl_3
  ];
  environment.variables = { 
    EDITOR = "vim"; 
  };

  networking = {
    hostName = "nix";
    useDHCP = false;

    interfaces.eth0.useDHCP = true;
    interfaces.eth1.useDHCP = true;

    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 2222 ];
      allowedUDPPorts = [ config.services.tailscale.port ];
      trustedInterfaces = [ "eth1" "tailscale0" ];
    };
    nat.enable = false;
    nftables = {
      enable = false;
      ruleset = "";
    };
  };

  time.timeZone = "America/New_York";

  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  services.xserver = {
    enable = false;
    layout = "us";
  };

  sound.enable = true;
  hardware.pulseaudio.enable = true;

  services = {
    avahi = {
      enable = true;
      publish = {
        enable = true;
        addresses = true;
        workstation = true;
      };
    };

    resolved = {
      enable = true;
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

    transmission = {
      enable = true;
    };

    tailscale = {
      enable = true;
      package = pkgs.tailscale;
    };
    vscode-server.enable = true;
  };

  programs = {
    neovim = {
      enable = true;
      vimAlias = true;
      viAlias = true;
      defaultEditor = true;
    };

    tmux = { enable = true; };

    zsh = {
      enable = true;
      enableBashCompletion = true;
      #enableCompletion = true;
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
        openssh.authorizedKeys.keys = [
          "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBLKmP5UUboT3SkiyHzY81/7UGG0SrVcSWxywkD8lpxYznrFz2uWT6zGfiQNj8FrLSwrh/AthIZJfe0LvbKEtTq8= home@secretive.cp-mba.local"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII5kFjpHHMhPxXAp54egnvuGVidd0g83jrw9AzD3AB5N cp@cp-win1"
        ];
      };

      builder = {
        isNormalUser = true;
        group = "users";
        shell = "/run/current-system/sw/bin/bash";
        openssh.authorizedKeys.keys = [
          "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBL2tKKY8LaqcHrt7ujkVsxqS8LWfeJi1egaFmz9mJAYh38nBaW6iBdtYDa6aTtEK1lRPNzL9VfuX+H7jc6++E8A= nix-build@secretive.cp-mba.local"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII5kFjpHHMhPxXAp54egnvuGVidd0g83jrw9AzD3AB5N cp@cp-win1"
        ];
      };
    };
  };

  system.stateVersion = "22.05";
})
