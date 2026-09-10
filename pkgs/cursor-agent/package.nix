{
  lib,
  fetchurl,
  stdenv,
  autoPatchelfHook,
  zlib,
}:

let
  inherit (stdenv) hostPlatform;
  version = "0-unstable-2026-09-08";
  sources = {
    x86_64-linux = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.09.08-6caf4ff/linux/x64/agent-cli-package.tar.gz";
      hash = "sha256-DXoR3QG2Uri5LQXMFPdp+8WjRCt4bNi2NgQfGJq4Hx4=";
    };
    aarch64-linux = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.09.08-6caf4ff/linux/arm64/agent-cli-package.tar.gz";
      hash = "sha256-FTrhgtuQgUdI1UTyomq8Bz5OTl3wuGer/Wne8P93qnE=";
    };
    x86_64-darwin = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.09.08-6caf4ff/darwin/x64/agent-cli-package.tar.gz";
      hash = "sha256-p4O01fk4s6x6kvZQVMZkItiUcTiJcCn9ycLoFkOXvBc=";
    };
    aarch64-darwin = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.09.08-6caf4ff/darwin/arm64/agent-cli-package.tar.gz";
      hash = "sha256-nEVsxDKtxHYgKisJwhoQlE/fSEs8pV3L+Tm7yM4w3L4=";
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
