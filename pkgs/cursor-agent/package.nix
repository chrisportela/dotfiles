{
  lib,
  fetchurl,
  stdenv,
  autoPatchelfHook,
  zlib,
}:

let
  inherit (stdenv) hostPlatform;
  version = "0-unstable-2026-05-09";
  sources = {
    x86_64-linux = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.05.09-0afadcc/linux/x64/agent-cli-package.tar.gz";
      hash = "sha256-IN0HzbHi5rrvi7fgjKcM5tl1T4TJ8lYlYtQC52NE9Xw=";
    };
    aarch64-linux = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.05.09-0afadcc/linux/arm64/agent-cli-package.tar.gz";
      hash = "sha256-xoTyqP7Nyq+dt2OyRR5mb3B8FQw7lPZuvBb0BcVW+4c=";
    };
    x86_64-darwin = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.05.09-0afadcc/darwin/x64/agent-cli-package.tar.gz";
      hash = "sha256-9MB+tFW+ZyvqRau/XVCjh1zms9kmyJzlzqDeMJ7Utos=";
    };
    aarch64-darwin = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.05.09-0afadcc/darwin/arm64/agent-cli-package.tar.gz";
      hash = "sha256-htzK+PAkiH7L1tQjr7yK0Pk+8kAXkSSG7tPImYMi0oY=";
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
