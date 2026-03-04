{
  description = "React Native (bare) development environment with pnpm";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    android-nixpkgs = {
      url = "github:tadfisher/android-nixpkgs/stable";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, android-nixpkgs, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ android-nixpkgs.overlays.default ];
          # Allow unfree packages (Xcode on macOS, Android Studio on Linux) required for RN builds
          config.allowUnfree = true;
        };

        jdk = pkgs.zulu17;
        nodejs = pkgs.nodejs_22;
        # Ruby 3.x for Gemfile / CocoaPods (Gemfile requires >= 3.0, < 4.1)
        ruby = pkgs.ruby_3_3;

        androidSdk = pkgs.androidSdk (sdkPkgs:
          with sdkPkgs; [
            cmdline-tools-latest
            build-tools-34-0-0
            platform-tools
            platforms-android-34
            emulator
          ]);

        # Writable SDK dir for shell hook (Nix store is read-only)
        androidSdkStorePath = "${androidSdk}/share/android-sdk";
      in {
        devShells.default = pkgs.mkShellNoCC {
          buildInputs = with pkgs;
            [
              nodejs
              nodePackages.pnpm
              watchman
              jdk
              androidSdk
              gradle
              ruby
              bundler
            ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin
            (with pkgs; [ cocoapods darwin.xcode_16_2 ])
            ++ pkgs.lib.optionals pkgs.stdenv.isLinux
            (with pkgs; [ android-studio-full ]);

          shellHook = ''
            export PATH="$PWD/node_modules/.bin:$PATH"

            # Writable Android SDK overlay (Gradle needs to write; Nix store is read-only)
            export ANDROID_HOME="$PWD/.android-sdk"
            export ANDROID_SDK_ROOT="$ANDROID_HOME"
            if [[ ! -d "$ANDROID_HOME" ]]; then
              echo "Copying Android SDK to writable directory (one-time)..."
              cp -r ${androidSdkStorePath} "$ANDROID_HOME"
            fi
            export PATH="$PATH:$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin"

            ${pkgs.lib.optionalString pkgs.stdenv.isDarwin ''
              export DEVELOPER_DIR="${pkgs.darwin.xcode_16_2}/Contents/Developer"
            ''}

            echo "React Native development environment ready!"
            echo "Node: $(node --version) | pnpm: $(pnpm --version) | Ruby: $(ruby --version)"
            echo "Run ./setup.sh MyApp then pnpm install to generate native projects."
          '';
        };
      });
}
