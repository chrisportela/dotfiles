{
  lib,
  fetchurl,
  stdenv,
  autoPatchelfHook,
  zlib,
}:

let
  inherit (stdenv) hostPlatform;
  version = "0-unstable-2026-06-04";
  sources = {
    x86_64-linux = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.06.04-5fd875e/linux/x64/agent-cli-package.tar.gz";
      hash = "sha256-VCWqsp+KAdN33j3H90VXOa1Zgp4IeeoMQpa9nuxSAwA=";
    };
    aarch64-linux = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.06.04-5fd875e/linux/arm64/agent-cli-package.tar.gz";
      hash = "sha256-840iUUKLt1duoq1LbxIFgwtRmvTna7A6Ofi4wbkEKkI=";
    };
    x86_64-darwin = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.06.04-5fd875e/darwin/x64/agent-cli-package.tar.gz";
      hash = "sha256-v0NSz3PECoPJg0C9UmmgpcuE9QEEJxdr9tZIkerKYiY=";
    };
    aarch64-darwin = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.06.04-5fd875e/darwin/arm64/agent-cli-package.tar.gz";
      hash = "sha256-GswPdGwhm/kweOTO66vWTpoptfRKN0bOmjCwFLdG0sc=";
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
