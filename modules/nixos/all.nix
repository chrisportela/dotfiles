# Aggregator: import all NixOS modules. Each module is toggled via its enable option.
{ ... }:
{
  imports = [
    ./nixpkgs.nix
    ./common.nix
    ./network.nix
    ./openssh.nix
    ./gaming.nix
    ./ftp.nix
    ./cafecitocloud
    ./local-llm
    ./nginx-cloudflare.nix
  ];
}
