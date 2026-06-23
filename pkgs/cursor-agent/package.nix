{
  lib,
  fetchurl,
  stdenv,
  autoPatchelfHook,
  zlib,
}:

let
  inherit (stdenv) hostPlatform;
  version = "2026.06.19-20-24-33-653a7fb";
  sources = {
    x86_64-linux = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.06.19-20-24-33-653a7fb/linux/x64/agent-cli-package.tar.gz";
      hash = "sha256-3xHrn1JaG2Leok/CiWtZezERrYqVcpZggXSD/zuWyy4=";
    };
    aarch64-linux = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.06.19-20-24-33-653a7fb/linux/arm64/agent-cli-package.tar.gz";
      hash = "sha256-6iiinIexiEKqXDXOHzKut1d0Mtg89A8zel0zeXna4Qc=";
    };
    x86_64-darwin = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.06.19-20-24-33-653a7fb/darwin/x64/agent-cli-package.tar.gz";
      hash = "sha256-HgxyZ1TPLnyJJJuvi8VrQhm33/rzD9kCwxy4Mp0D9C0=";
    };
    aarch64-darwin = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.06.19-20-24-33-653a7fb/darwin/arm64/agent-cli-package.tar.gz";
      hash = "sha256-Qa22+f5+x5+4sHesqp24d9GlKqPp6xBJG7BFxz6LUVU=";
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
