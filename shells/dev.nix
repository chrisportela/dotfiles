{ pkgs }: pkgs.mkShell {
  RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";

  nativeBuildInputs = with pkgs; [
    pkg-config
    openssl
    stdenv.cc.cc.lib
  ];

  # The Nix packages provided in the environment
  packages = (with pkgs; [
    rustToolchain
    python311
    nodejs_20
    go
  ]) ++ pkgs.lib.optionals pkgs.stdenv.isDarwin (with pkgs; [
    # libiconv
    # darwin.apple_sdk.frameworks.SystemConfiguration
  ])
  ++ pkgs.lib.optionals pkgs.stdenv.isLinux (with pkgs; [ ]);
}
