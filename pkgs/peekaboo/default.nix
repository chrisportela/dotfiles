{
  lib,
  stdenvNoCC,
  fetchurl,
}:

stdenvNoCC.mkDerivation rec {
  pname = "peekaboo";
  version = "3.0.0-beta3";

  src = fetchurl {
    url = "https://github.com/steipete/Peekaboo/releases/download/v${version}/peekaboo-macos-universal.tar.gz";
    hash = "sha256-d+rfb9XFTqxktIRNXMiHiQttb0XUmvYbBcbinqLL0kU=";
  };

  sourceRoot = "peekaboo-macos-universal";

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp peekaboo $out/bin/
    runHook postInstall
  '';

  meta = {
    description = "macOS CLI tool that enables AI agents to capture screenshots and perform visual queries";
    homepage = "https://github.com/steipete/Peekaboo";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin;
    mainProgram = "peekaboo";
  };
}
