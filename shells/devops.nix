{ pkgs }:
pkgs.mkShell {
  # The Nix packages provided in the environment
  packages =
    (with pkgs; [
      python311
      nodejs_20
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
