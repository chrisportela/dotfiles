{ lib, config, pkgs, inputs, ... }:
{
  imports = [
    ./openssh.nix
    ./firewall.nix
    ./nginx-cloudflare.nix
  ];

  options = { };

  config = {
    networking.firewall.allowedTCPPorts = [ 80 443 ];

    environment.systemPackages = with pkgs; [ goaccess lnav ];

    services.tailscale = {
      enable = true;
      package = pkgs.tailscale;
      useRoutingFeatures = "server";
    };

    services.vscode-server.enable = true;

    security.sudo.wheelNeedsPassword = true;

    services.logrotate = { enable = true; };
  };
}
