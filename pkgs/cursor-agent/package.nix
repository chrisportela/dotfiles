{
  lib,
  fetchurl,
  stdenv,
  autoPatchelfHook,
  zlib,
}:

let
  inherit (stdenv) hostPlatform;
  version = "0-unstable-2026-09-15";
  sources = {
    x86_64-linux = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.09.15-d2fe57e/linux/x64/agent-cli-package.tar.gz";
      hash = "sha256-S3sCbdEE6TWyFsxS+QWlYNdB/ICkpNYu9lVzW5ahXJc=";
    };
    aarch64-linux = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.09.15-d2fe57e/linux/arm64/agent-cli-package.tar.gz";
      hash = "sha256-LXQcEsPuelBVhFee+yig7jH/E/78HzR+LTtDaIwEYg0=";
    };
    x86_64-darwin = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.09.15-d2fe57e/darwin/x64/agent-cli-package.tar.gz";
      hash = "sha256-Lj+AO4eZQTDlT5ILXH+kaRf4A0x2IwjUW3XXATWX6Xo=";
    };
    aarch64-darwin = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.09.15-d2fe57e/darwin/arm64/agent-cli-package.tar.gz";
      hash = "sha256-9RV5oeoXJcK+vRoUBk1SvepeBar/R8+n1bXQ0HqNP7w=";
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
