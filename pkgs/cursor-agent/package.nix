{
  lib,
  fetchurl,
  stdenv,
  autoPatchelfHook,
  zlib,
}:

let
  inherit (stdenv) hostPlatform;
  version = "0-unstable-2026-04-17";
  sources = {
    x86_64-linux = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.04.17-787b533/linux/x64/agent-cli-package.tar.gz";
      hash = "sha256-lCsrWDI5SXcV8jkDNuuOLfNnNwO9FnvVn3vjOifhXFo=";
    };
    aarch64-linux = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.04.17-787b533/linux/arm64/agent-cli-package.tar.gz";
      hash = "sha256-mFGR/8YG2hMX4TmfmTBkgfWGQ/NF7SJSAzsBFQTHgM4=";
    };
    x86_64-darwin = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.04.17-787b533/darwin/x64/agent-cli-package.tar.gz";
      hash = "sha256-7nghaUUppXQOvezl9NWtFV3SmN7gOW69dFc1mRW91Xk=";
    };
    aarch64-darwin = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.04.17-787b533/darwin/arm64/agent-cli-package.tar.gz";
      hash = "sha256-A54ySMrLb2283LGbr/rBUyCVaCM2xXCKcWUUpCSVIcI=";
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
