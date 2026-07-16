{
  lib,
  fetchurl,
  stdenv,
  autoPatchelfHook,
  zlib,
}:

let
  inherit (stdenv) hostPlatform;
  version = "0-unstable-2026-07-09";
  sources = {
    x86_64-linux = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.07.09-a3815c0/linux/x64/agent-cli-package.tar.gz";
      hash = "sha256-x8HzIknO25nMIM1O7R+TCNwimaeMKDu8bv1tZYzUl34=";
    };
    aarch64-linux = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.07.09-a3815c0/linux/arm64/agent-cli-package.tar.gz";
      hash = "sha256-EbK2gBE2oRo2MqSxCA6jv8fZfQpoOCvp7eH69TMyB/s=";
    };
    x86_64-darwin = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.07.09-a3815c0/darwin/x64/agent-cli-package.tar.gz";
      hash = "sha256-BmxJn27ENzQlQzfEk67sWqu0pq5tbffaIU+obO2p5F0=";
    };
    aarch64-darwin = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.07.09-a3815c0/darwin/arm64/agent-cli-package.tar.gz";
      hash = "sha256-AJ7oV9SfF8EOUDXjOITrJY0fODnB1SvbNfNaEXNp394=";
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
