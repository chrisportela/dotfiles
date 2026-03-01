{
  cafecitocloud = ./cafecitocloud;
  common = ./common.nix;
  # ddc = ./ddc.nix;
  local-llm = ./local-llm;
  gaming = ./gaming.nix;
  network = ./network.nix;
  nixpkgs = ./nixpkgs.nix;
  nginx-cloudflare = ./nginx-cloudflare.nix;
  openssh = ./openssh.nix;
  ftp = ./ftp.nix;
  # Single module that imports all of the above; use this in host configs.
  default = ./all.nix;
}
