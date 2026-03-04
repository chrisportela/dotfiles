# Build a home-manager configuration with shared base modules. Called as:
# simpleHomeConfig = (import ./lib/simple-home-config.nix) inputs;
inputs:
{ pkgs, home-manager ? inputs.home-manager, username ? "cmp", options ? { } }:
home-manager.lib.homeManagerConfiguration {
  inherit pkgs;
  modules = [
    ../modules/home/nixpkgs.nix
    ../modules/home/default.nix
    {
      allowedUnfree = [ "vault-bin" "terraform" ];
      home.username = username;
    }
    options
  ];
}
