{ pkgs }:
pkgs.mkShellNoCC {
  # The Nix packages provided in the environment
  packages =
    (with pkgs; [
      python3
      nodejs
      terraformer
      terraforming
      awscli2
      google-cloud-sdk
      doctl
      terraformFull
    ])
    ++ pkgs.lib.optionals pkgs.stdenv.isDarwin (with pkgs; [ ])
    ++ pkgs.lib.optionals pkgs.stdenv.isLinux (with pkgs; [ ]);
}
