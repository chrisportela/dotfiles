{ lib, config, pkgs, inputs, ... }:
{
  imports = [
    inputs.agenix.nixosModules.default
    inputs.vscode-server.nixosModule
    inputs.dotfiles.nixosModules.deploy_rs_overlay
    ./base.nix
  ];

  networking = {
    firewall = {
      allowedTCPPorts = [ 443 ] ++ config.services.openssh.ports;
      allowedUDPPorts = [ config.services.tailscale.port ];
      enable = true;
      trustedInterfaces = [ "tailscale0" ];
    };
  };

  environment = {
    systemPackages = with pkgs; [
      bind
      curl
      fast-cli
      git
      goaccess
      htop
      inetutils
      ipcalc
      iperf3
      lnav
      neovim
      nftables
      nixpkgs-fmt
      ookla-speedtest
      speedtest-cli
      tcpdump
      tmux
      traceroute
      wget
    ];
  };

  programs = {
    neovim = {
      enable = true;
      viAlias = true;
      vimAlias = true;
    };

    zsh.enable = true;

    tmux = {
      enable = true;
      terminal = "screen-256color";
      clock24 = true;
      baseIndex = 1;
      newSession = true;
      plugins = with pkgs.tmuxPlugins; [ sensible ];
    };
  };

  services.openssh = {
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

  services.tailscale = {
    enable = true;
    package = pkgs.tailscale;
    useRoutingFeatures = "server";
  };
  services.vscode-server.enable = true;

  security.sudo.wheelNeedsPassword = true;

  services.logrotate = {
    enable = true;
  };

  system.stateVersion = "23.05";
}
