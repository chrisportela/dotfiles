{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  swift6,
  cacert,
  git,
}:

let
  version = "3.0.0-beta3";

  src = fetchFromGitHub {
    owner = "steipete";
    repo = "Peekaboo";
    rev = "v${version}";
    hash = "sha256-9DS/9cJ0GTiWEKmGUj0gvDIx6sfrvXhfc3+GgnnI73w=";
    fetchSubmodules = true;
  };

  # Fixed-output derivation to resolve SPM dependencies with network access.
  spmDeps = stdenvNoCC.mkDerivation {
    pname = "peekaboo-spm-deps";
    inherit version src;

    nativeBuildInputs = [
      swift6
      git
      cacert
    ];

    # FOD: allow network access by specifying a fixed output hash.
    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    outputHash = lib.fakeHash;

    buildPhase = ''
      export HOME=$TMPDIR
      export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt

      cd Apps/CLI
      swift package resolve
    '';

    installPhase = ''
      mkdir -p $out
      cp -r .build $out/
    '';
  };

in
stdenvNoCC.mkDerivation {
  pname = "peekaboo-git";
  inherit version src;

  nativeBuildInputs = [
    swift6
    git
  ];

  configurePhase = ''
    runHook preConfigure

    # Copy pre-resolved SPM dependencies into the build directory.
    cd Apps/CLI
    cp -r ${spmDeps}/.build .build
    chmod -R u+w .build

    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild

    export HOME=$TMPDIR
    swift build -c release --skip-update

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
