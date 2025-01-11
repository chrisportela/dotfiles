{ pkgs }: pkgs.mkShell {
  RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";

  nativeBuildInputs = with pkgs; [
    pkg-config
    openssl
    stdenv.cc.cc.lib
  ];

  # The Nix packages provided in the environment
  packages = (with pkgs; [
    # Basics
    gnumake
    getopt

    # Rust
    rustToolchain

    # Python
    python3
    poetry
    uv
    ruff

    # Go
    go

    # Node
    nodejs_20
    pnpm
  ]) ++ pkgs.lib.optionals pkgs.stdenv.isDarwin (with pkgs; [
    # libiconv
    # darwin.apple_sdk.frameworks.SystemConfiguration
  ])
  ++ pkgs.lib.optionals pkgs.stdenv.isLinux (with pkgs; [ ]);
}
