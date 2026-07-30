{
  lib,
  fetchurl,
  stdenv,
  autoPatchelfHook,
  zlib,
}:

let
  inherit (stdenv) hostPlatform;
  version = "0-unstable-2026-07-23";
  sources = {
    x86_64-linux = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.07.23-e383d2b/linux/x64/agent-cli-package.tar.gz";
      hash = "sha256-cCrVlSE77l3wJovp+AoZ8p/M6qKkL8VeOfK1GZBR8MQ=";
    };
    aarch64-linux = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.07.23-e383d2b/linux/arm64/agent-cli-package.tar.gz";
      hash = "sha256-9AuZZHyyTg2ohel2IKIEgDTx/olhkQ1XPYJ9d8TSbcs=";
    };
    x86_64-darwin = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.07.23-e383d2b/darwin/x64/agent-cli-package.tar.gz";
      hash = "sha256-9EGU38tBRo+Fv7TlOXisCYoqeM5imAZJDDK4C0CXWqI=";
    };
    aarch64-darwin = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.07.23-e383d2b/darwin/arm64/agent-cli-package.tar.gz";
      hash = "sha256-8uslhR8gedzfBVioFuBsQC0Yer/KkyVdNRZwIEOeu/I=";
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
