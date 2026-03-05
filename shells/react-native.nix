{ pkgs, android-nixpkgs }:

let
  inherit (pkgs) lib;
  # For macOS, use jdk8 which is compatible with React Native
  jdk = pkgs.zulu17;

  # Use nodejs from nixpkgs
  nodejs = pkgs.nodejs_24;

  android-nixpkgs' = pkgs.callPackage android-nixpkgs {
    channel = "stable";
    accept_license = true;
  };

  # Configure Android SDK
  android-sdk = let
    apiVersion = "34";
    system = pkgs.stdenv.system;
    in android-nixpkgs'.sdk.${system} (

    sdkPkgs: with sdkPkgs; [
      sdkPkgs."build-tools-${apiVersion}-0-0"
      cmdline-tools-latest
      emulator
      platform-tools
      sdkPkgs."platforms-android-${apiVersion}"

      # Other useful packages for a development environment.
      # ndk-26-1-10909125
      # skiaparser-3
      # "sources-android-${apiVersion}"
    ]++ lib.optionals (system == "aarch64-darwin") [
      sdkPkgs."system-images-android-${apiVersion}-google-apis-arm64-v8a"
      sdkPkgs."system-images-android-${apiVersion}-google-apis-playstore-arm64-v8a"
    ]
    ++ lib.optionals (system == "x86_64-darwin" || system == "x86_64-linux") [
      sdkPkgs."system-images-android-${apiVersion}-google-apis-x86-64"
      sdkPkgs."system-images-android-${apiVersion}-google-apis-playstore-x86-64"
    ]
  );
  # xcodeenv = import (nixpkgs + "/pkgs/development/mobile/xcodeenv") { inherit (pkgs) callPackage; };
in
pkgs.mkShellNoCC {
  buildInputs =
    with pkgs;
    [
      # Node.js environment
      nodejs
      nodePackages.yarn

      # For file watching
      watchman

      # Android development
      jdk
      android-sdk
      gradle

      # Ruby / Bundler for Gemfile and CocoaPods (iOS)
      ruby_3_3
      bundler
    ]
    ++ lib.optionals pkgs.stdenv.isDarwin (
      with pkgs;
      [
        # iOS dependencies (macOS only)
        cocoapods
        ios-deploy
        sourcekit-lsp
        # apple-sdk_15
        # (xcodeenv.composeXcodeWrapper { versions = [ "16.2" ]; })
        darwin.xcode_26_2_Apple_silicon
      ]
    )
    ++ lib.optionals pkgs.stdenv.isLinux (with pkgs; [ android-studio-full ]);

  # TODO: Error building android - SDK not writable
  # TODO: Error building iOS with proper DEVELOPER_DIR var (mess of output)
  # TODO: Incorrect DEVELOPER_DIR, uses Nix toolchain.

  # Shell hook to configure environment variables
  shellHook =
    let
      xcodePaths = lib.optionals pkgs.stdenv.isDarwin ''
        # If on macOS, set Xcode-related paths
        if [[ "$(uname)" == "Darwin" ]]; then
          # export PATH=$(echo $PATH | sd "${pkgs.xcbuild.xcrun}/bin" "")
          # unset DEVELOPER_DIR
          # unset SDKROOT
          export DEVELOPER_DIR="${pkgs.darwin.xcode_26_2_Apple_silicon}/Contents/Developer"
          # # Ensure Xcode command line tools are used for iOS builds
          # export PATH="$DEVELOPER_DIR/Contents/Developer/usr/bin:$PATH"
        fi
      '';
    in
    ''
      # Android configuration
      export ANDROID_HOME=${android-sdk}/share/android-sdk
      export ANDROID_SDK_ROOT=${android-sdk}/share/android-sdk
      export JAVA_HOME=${jdk.home}
      # export PATH=$PATH:$ANDROID_HOME/emulator
      # export PATH=$PATH:$ANDROID_HOME/platform-tools
      # export PATH=$PATH:$ANDROID_HOME/tools/bin

      # Add node_modules/.bin to PATH
      export PATH="$PWD/node_modules/.bin:$PATH"

      # Xcode Paths (only if darwin)
      ${xcodePaths}

      echo "React Native development environment ready!"
    '';

    meta = with pkgs.lib; {
      broken = pkgs.stdenv.system == "aarch64-linux";
    };
}
