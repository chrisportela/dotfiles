{
  pkgs,
  android-nixpkgs,
}:

let
  # For macOS, use jdk8 which is compatible with React Native
  jdk = pkgs.zulu17;

  # Use nodejs from nixpkgs
  nodejs = pkgs.nodejs_24;

  _android-nixpkgs = pkgs.callPackage android-nixpkgs { };

  # Configure Android SDK
  androidSdk = _android-nixpkgs.sdk (
    sdkPkgs: with sdkPkgs; [
      cmdline-tools-latest
      build-tools-35-0-0
      platform-tools
      platforms-android-35
      emulator
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

      # iOS development
      ios-deploy
      sourcekit-lsp

      # Android development
      jdk
      androidSdk
      gradle

      # Ruby / Bundler for Gemfile and CocoaPods (iOS)
      ruby_3_3
      bundler
    ]
    ++ pkgs.lib.optionals pkgs.stdenv.isDarwin (
      with pkgs.pkgsUnstable;
      [
        # iOS dependencies (macOS only)
        cocoapods
        # apple-sdk_15
        # (xcodeenv.composeXcodeWrapper { versions = [ "16.2" ]; })
        darwin.xcode_26_2_Apple_silicon
      ]
    )
    ++ pkgs.lib.optionals pkgs.stdenv.isLinux (with pkgs; [ android-studio-full ]);

  # TODO: Error building android - SDK not writable
  # TODO: Error building iOS with proper DEVELOPER_DIR var (mess of output)
  # TODO: Incorrect DEVELOPER_DIR, uses Nix toolchain.

  # Shell hook to configure environment variables
  shellHook =
    let
      xcodePaths = pkgs.lib.optionals pkgs.stdenv.isDarwin ''
        # If on macOS, set Xcode-related paths
        if [[ "$(uname)" == "Darwin" ]]; then
          # export PATH=$(echo $PATH | sd "${pkgs.xcbuild.xcrun}/bin" "")
          # unset DEVELOPER_DIR
          # unset SDKROOT
          export DEVELOPER_DIR="${pkgs.pkgsUnstable.darwin.xcode_26_2_Apple_silicon}/Contents/Developer"
          # # Ensure Xcode command line tools are used for iOS builds
          # export PATH="$DEVELOPER_DIR/Contents/Developer/usr/bin:$PATH"
        fi
      '';
    in
    ''
      # Android configuration
      # export ANDROID_HOME=${androidSdk}/libexec/android-sdk
      # export ANDROID_SDK_ROOT=$ANDROID_HOME
      # export PATH=$PATH:$ANDROID_HOME/emulator
      # export PATH=$PATH:$ANDROID_HOME/platform-tools
      # export PATH=$PATH:$ANDROID_HOME/tools/bin

      # Add node_modules/.bin to PATH
      export PATH="$PWD/node_modules/.bin:$PATH"

      # Xcode Paths (only if darwin)
      ${xcodePaths}

      echo "React Native development environment ready!"
    '';
}
