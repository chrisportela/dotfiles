{
  lib,
  fetchurl,
  stdenv,
  autoPatchelfHook,
  zlib,
}:

let
  inherit (stdenv) hostPlatform;
  version = "0-unstable-2026-06-29";
  sources = {
    x86_64-linux = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.06.29-2ad2186/linux/x64/agent-cli-package.tar.gz";
      hash = "sha256-mE4iVRoxXrbVFsLoBjUAJD3Dy3jBOaEPUp3sj/TlvJs=";
    };
    aarch64-linux = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.06.29-2ad2186/linux/arm64/agent-cli-package.tar.gz";
      hash = "sha256-RiDU7x76KjPp+0PbyH2nrCe5YMuuAdsk33B/vOzDh5I=";
    };
    x86_64-darwin = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.06.29-2ad2186/darwin/x64/agent-cli-package.tar.gz";
      hash = "sha256-syXRFbhjM+Ub3xsxnXtMNN/BaV8WOfYzxHtMQPirQE0=";
    };
    aarch64-darwin = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.06.29-2ad2186/darwin/arm64/agent-cli-package.tar.gz";
      hash = "sha256-V7QjeS6yYeWwEjGNL7kGx5e/gl/MiReuytiyOM07PNQ=";
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
