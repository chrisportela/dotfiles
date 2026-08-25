# Aggregator: import all Darwin modules.
{ ... }:
{
  imports = [
    ./common.nix
    ./nixpkgs.nix
    ./stats.nix
    ./forgejo-runner
    ./nix-cache-push
  ];
}
