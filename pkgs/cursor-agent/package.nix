{
  lib,
  fetchurl,
  stdenv,
  autoPatchelfHook,
  zlib,
}:

let
  inherit (stdenv) hostPlatform;
  version = "0-unstable-2026-05-28";
  sources = {
    x86_64-linux = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.05.28-a70ca7c/linux/x64/agent-cli-package.tar.gz";
      hash = "sha256-f4tqCTk+C4SyiMxpUrKS/JjRV3X2RMwBsLmqTwSyaN8=";
    };
    aarch64-linux = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.05.28-a70ca7c/linux/arm64/agent-cli-package.tar.gz";
      hash = "sha256-BaCrNh4Dhymrol/n9AdTGz6EMpEuSZ0L/98d2g54M+k=";
    };
    x86_64-darwin = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.05.28-a70ca7c/darwin/x64/agent-cli-package.tar.gz";
      hash = "sha256-6E3G5PbnfLIo3HyQ+/Ez6MdjJvHF6cI2IwfAclhsZjM=";
    };
    aarch64-darwin = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.05.28-a70ca7c/darwin/arm64/agent-cli-package.tar.gz";
      hash = "sha256-vZs2VMzhDWpYYl7yDr3qqmtQM0nVWbaf+pRLFM/0ILA=";
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
