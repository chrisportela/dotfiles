{
  lib,
  fetchurl,
  stdenv,
  autoPatchelfHook,
  zlib,
}:

let
  inherit (stdenv) hostPlatform;
  version = "0-unstable-2026-07-20";
  sources = {
    x86_64-linux = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.07.20-8cc9c0b/linux/x64/agent-cli-package.tar.gz";
      hash = "sha256-bp8XJH/+tfj34iRrS81rsmyy1an5pLABLJqA2GjtJbQ=";
    };
    aarch64-linux = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.07.20-8cc9c0b/linux/arm64/agent-cli-package.tar.gz";
      hash = "sha256-KYYVKyg8cKZmsBUDWy6ZqW0Tr9JmClh7hjlBfP3RR/s=";
    };
    x86_64-darwin = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.07.20-8cc9c0b/darwin/x64/agent-cli-package.tar.gz";
      hash = "sha256-5F7XyF4gCAMQd4/1onBQyWF5iNxeda0/rwCvgeT34BE=";
    };
    aarch64-darwin = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.07.20-8cc9c0b/darwin/arm64/agent-cli-package.tar.gz";
      hash = "sha256-18Xuna0+L872ki9eGvxlvZxh3AdxL2RY4GalK+UrBy0=";
    };
  };
in
stdenv.mkDerivation {
  pname = "cursor-agent";
  inherit version;

  src = sources.${hostPlatform.system};

  nativeBuildInputs = lib.optionals hostPlatform.isLinux [
    autoPatchelfHook
  ];

  buildInputs = lib.optionals hostPlatform.isLinux [
    stdenv.cc.cc.lib
    zlib
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share/cursor-agent
    cp -r * $out/share/cursor-agent/
    ln -s $out/share/cursor-agent/cursor-agent $out/bin/cursor-agent

    runHook postInstall
  '';

  passthru = {
    inherit sources;
    updateScript = ./update.sh;
  };

  meta = {
    description = "Cursor AI agent CLI for agentic coding from the terminal";
    homepage = "https://cursor.com/cli";
    license = lib.licenses.unfree;
    platforms = builtins.attrNames sources;
    mainProgram = "cursor-agent";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
