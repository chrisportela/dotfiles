{
  lib,
  fetchurl,
  stdenv,
  autoPatchelfHook,
  zlib,
}:

let
  inherit (stdenv) hostPlatform;
  version = "0-unstable-2026-09-28";
  sources = {
    x86_64-linux = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.09.28-64d2043/linux/x64/agent-cli-package.tar.gz";
      hash = "sha256-bkzZNqSGa4p3xQ/1GlZEYNcVdy+rxHegGqDwRV2VWfA=";
    };
    aarch64-linux = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.09.28-64d2043/linux/arm64/agent-cli-package.tar.gz";
      hash = "sha256-xzdZmyfT2NZ0PHK0hyBOM186jqL9uvGDAu4gemRv/Y0=";
    };
    x86_64-darwin = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.09.28-64d2043/darwin/x64/agent-cli-package.tar.gz";
      hash = "sha256-Pv4N/y89kqHoE54z/vGCgBVWtX7VCmr9e6wZxPrQlUk=";
    };
    aarch64-darwin = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.09.28-64d2043/darwin/arm64/agent-cli-package.tar.gz";
      hash = "sha256-wNfpzS5iQ4YQuIbTQ5kH3B+YwpI7B7OkFBbMkZqvU8c=";
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
