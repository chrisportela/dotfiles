# Aggregator: import all Darwin modules.
{ ... }:
{
  imports = [
    ./common.nix
    ./nixpkgs.nix
    ./stats.nix
  ];
}
