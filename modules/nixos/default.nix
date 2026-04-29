{
  agent-vms = ./agent-vms;
  cafecitocloud = ./cafecitocloud;
  common = ./common.nix;
  # ddc = ./ddc.nix;
  gaming = ./gaming.nix;
  memory-protection = ./memory-protection;
  network = ./network.nix;
  nixpkgs = ./nixpkgs.nix;
  nginx-cloudflare = ./nginx-cloudflare.nix;
  openssh = ./openssh.nix;
  # Single module that imports all of the above; use this in host configs.
  default = ./all.nix;
}
