# Aggregator: import all NixOS modules. Each module is toggled via its enable option.
{ ... }:
{
  imports = [
    ./agent-vms
    ./nixpkgs.nix
    ./common.nix
    ./network.nix
    ./openssh.nix
    ./gaming.nix
    ./cafecitocloud
    ./forgejo-runner
    ./memory-protection
    ./nginx-cloudflare.nix
  ];
}
