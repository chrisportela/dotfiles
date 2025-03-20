{
  pkgs ? import <nixpkgs> { },
  android-nixpkgs ? import <android-nixpkgs> { },
}:

let
  # For macOS, use jdk8 which is compatible with React Native
  jdk = pkgs.zulu17;

  # Use nodejs from nixpkgs
  nodejs = pkgs.nodejs_22;

  _android-nixpkgs = pkgs.callPackage android-nixpkgs { };

  # Configure Android SDK
  androidSdk = _android-nixpkgs.sdk (
    sdkPkgs: with sdkPkgs; [
      cmdline-tools-latest
      build-tools-34-0-0
      platform-tools
      platforms-android-34
      emulator
    ]
  );
in
pkgs.mkShell {
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
      androidSdk
      gradle

      # iOS dependencies (macOS only)
      cocoapods
    ]
    ++ pkgs.lib.optionals pkgs.stdenv.isLinux (with pkgs; [ android-studio-stable ]);

  # TODO: Error building android - SDK not writable
  # TODO: Error building iOS with proper DEVELOPER_DIR var (mess of output)
  # TODO: Incorrect DEVELOPER_DIR, uses Nix toolchain.

  # Shell hook to configure environment variables
  shellHook = ''
    # Android configuration
    # export ANDROID_HOME=${androidSdk}/libexec/android-sdk
    # export ANDROID_SDK_ROOT=$ANDROID_HOME
    # export PATH=$PATH:$ANDROID_HOME/emulator
    # export PATH=$PATH:$ANDROID_HOME/platform-tools
    # export PATH=$PATH:$ANDROID_HOME/tools/bin

    # Add node_modules/.bin to PATH
    export PATH="$PWD/node_modules/.bin:$PATH"

    # If on macOS, set Xcode-related paths
    if [[ "$(uname)" == "Darwin" ]]; then
      export DEVELOPER_DIR=$(xcode-select -p)
      # Ensure Xcode command line tools are used for iOS builds
      export PATH="/usr/bin:$PATH"
    fi

    echo "React Native development environment ready!"
  '';
}
