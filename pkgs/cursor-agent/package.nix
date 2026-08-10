{
  lib,
  fetchurl,
  stdenv,
  autoPatchelfHook,
  zlib,
}:

let
  inherit (stdenv) hostPlatform;
  version = "0-unstable-2026-08-04";
  sources = {
    x86_64-linux = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.08.04-aaa8809/linux/x64/agent-cli-package.tar.gz";
      hash = "sha256-4oIGjctc3WaLjOLjRWxYvhO7ZKg04a1J+FNLXNeqL+U=";
    };
    aarch64-linux = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.08.04-aaa8809/linux/arm64/agent-cli-package.tar.gz";
      hash = "sha256-1RliiSkqZgtZgHrFCMmsNuweGhp+RpevPvaCT96phO4=";
    };
    x86_64-darwin = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.08.04-aaa8809/darwin/x64/agent-cli-package.tar.gz";
      hash = "sha256-OyuV+mgXRfMLHQMeZ9I8GhmTTtQvOd6jq30tdygyCqU=";
    };
    aarch64-darwin = fetchurl {
      url = "https://downloads.cursor.com/lab/2026.08.04-aaa8809/darwin/arm64/agent-cli-package.tar.gz";
      hash = "sha256-/B0mdiL/gGoz2/UWFIuf05V4B/TZMcdjEYwmn5K1Nfw=";
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
