{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  darwin,
  cacert,
  git,
}:

let
  xcode = darwin.xcode_26_2_Apple_silicon;
  developerDir = "${xcode}/Contents/Developer";
  toolchain = "${developerDir}/Toolchains/XcodeDefault.xctoolchain";
  sdkRoot = "${developerDir}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";
in
stdenvNoCC.mkDerivation rec {
  pname = "peekaboo-git";
  version = "3.0.0-unstable-2026-03-14";

  src = fetchFromGitHub {
    owner = "steipete";
    repo = "Peekaboo";
    rev = "590a94a5ee6dafb4bb4724717a9ccb2ae557c6db";
    hash = "sha256-T6mkcKlBfEAqr+yg92oABaIUT7o7wZePMv+iH8UUhNc=";
    fetchSubmodules = true;
  };

  nativeBuildInputs = [
    git
    cacert
  ];

  buildPhase = ''
    runHook preBuild

    export HOME=$TMPDIR
    export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt
    export DEVELOPER_DIR=${developerDir}
    export SDKROOT=${sdkRoot}
    export PATH=${toolchain}/usr/bin:$PATH

    cd Apps/CLI
    swift package resolve --disable-sandbox
    swift build -c release --disable-sandbox

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp .build/release/peekaboo $out/bin/

    runHook postInstall
  '';

  # Don't strip Swift binaries
  dontStrip = true;

  meta = {
    description = "macOS CLI tool for AI-powered screenshot capture and visual queries (built from source)";
    homepage = "https://github.com/steipete/Peekaboo";
    license = lib.licenses.mit;
    platforms = [ "aarch64-darwin" ];
    mainProgram = "peekaboo";
  };
}
