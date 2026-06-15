{
  lib,
  fetchurl,
  stdenv,
  autoPatchelfHook,
  zlib,
}:

let
  inherit (stdenv) hostPlatform;
  version = "2026.06.15-18-00-12-6f5a2cf";
  sources = {
    x86_64-linux = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.06.15-18-00-12-6f5a2cf/linux/x64/agent-cli-package.tar.gz";
      hash = "sha256-M7IrDE/QOXqJ/BuQjkU2uwqPsJ2v+XrPUZ++x2VpzLM=";
    };
    aarch64-linux = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.06.15-18-00-12-6f5a2cf/linux/arm64/agent-cli-package.tar.gz";
      hash = "sha256-cD46R6R7uq5NVLSPhgp4Ctrla/2/uM/M9Xjd29VyE4I=";
    };
    x86_64-darwin = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.06.15-18-00-12-6f5a2cf/darwin/x64/agent-cli-package.tar.gz";
      hash = "sha256-brifvXk3SqyBReovGXk8+j9hONdK8dRdT+KZxkRkKnQ=";
    };
    aarch64-darwin = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.06.15-18-00-12-6f5a2cf/darwin/arm64/agent-cli-package.tar.gz";
      hash = "sha256-Se2EDjq0ahKZaJB9v+8G5Fnu+y/KHE/sU461YOG1m6w=";
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
