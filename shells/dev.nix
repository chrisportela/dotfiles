{ pkgs }:
let
  gotools = pkgs.gotools.overrideAttrs (
    finalAttrs: previousAttrs: {
      postInstall =
        previousAttrs.postInstall
        + ''
          mv $out/bin/play $out/bin/goplay
        '';
    }
  );
in
pkgs.mkShell {
  RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";

  nativeBuildInputs = with pkgs; [
    pkg-config
    openssl
    stdenv.cc.cc.lib
  ];

  # The Nix packages provided in the environment
  packages =
    (with pkgs; [
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

      # Go + vscode tooling
      go
      gotools
      gopls
      gotests
      gomodifytags
      impl
      delve
      golangci-lint

      # Node
      nodejs_20
      pnpm
    ])
    ++ pkgs.lib.optionals pkgs.stdenv.isDarwin (
      with pkgs;
      [
        # libiconv
        # darwin.apple_sdk.frameworks.SystemConfiguration
      ]
    )
    ++ pkgs.lib.optionals pkgs.stdenv.isLinux (with pkgs; [ ]);
}
