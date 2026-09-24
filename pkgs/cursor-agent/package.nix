{
  lib,
  fetchurl,
  stdenv,
  autoPatchelfHook,
  zlib,
}:

let
  inherit (stdenv) hostPlatform;
  version = "0-unstable-2026-09-23";
  sources = {
    x86_64-linux = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.09.23-86fc751/linux/x64/agent-cli-package.tar.gz";
      hash = "sha256-dA3Z1uta7DbKkOrt+f1eLEic1nTWm1FHs8JnDwLZd20=";
    };
    aarch64-linux = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.09.23-86fc751/linux/arm64/agent-cli-package.tar.gz";
      hash = "sha256-ONFILJRRcpJueAIG/OjMUcZ91PlhYrzsaAkDqnDYBBc=";
    };
    x86_64-darwin = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.09.23-86fc751/darwin/x64/agent-cli-package.tar.gz";
      hash = "sha256-gJM1zUqS98EaIPYFITWFthNse/5nIgafrPlOmI0+0Oc=";
    };
    aarch64-darwin = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.09.23-86fc751/darwin/arm64/agent-cli-package.tar.gz";
      hash = "sha256-+j/hPVWJxYb/EyokwW7qlvuO/eiK/e/dzRHYD6GZ86U=";
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
