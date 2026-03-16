{
  lib,
  stdenvNoCC,
  fetchurl,
  xar,
  cpio,
}:

stdenvNoCC.mkDerivation rec {
  pname = "swift6";
  version = "6.2.4";

  src = fetchurl {
    url = "https://download.swift.org/swift-${version}-release/xcode/swift-${version}-RELEASE/swift-${version}-RELEASE-osx.pkg";
    hash = "sha256-nJRjf9qDEpAaCOVyplHDoYpnJomthn+WySV7Q3dRWek=";
  };

  nativeBuildInputs = [
    xar
    cpio
  ];

  unpackPhase = ''
    xar -xf $src
    cd swift-${version}-RELEASE-osx-package.pkg
    cat Payload | gunzip | cpio -id
    cd ..
  '';

  installPhase = ''
    runHook preInstall

    src_dir=swift-${version}-RELEASE-osx-package.pkg

    mkdir -p $out
    cp -r $src_dir/usr/* $out/

    # The toolchain's lld doesn't support macOS linking.
    # Swift's toolchain is designed to use Apple's system linker.
    cat > $out/bin/ld << WRAPPER
    #!/bin/sh
    exec /usr/bin/ld "\$@"
    WRAPPER
    chmod +x $out/bin/ld

    runHook postInstall
  '';

  # Don't patch binaries - they're signed macOS binaries
  dontStrip = true;
  dontFixup = true;

  meta = {
    description = "Pre-built Swift ${version} toolchain from swift.org";
    homepage = "https://www.swift.org";
    license = lib.licenses.asl20;
    platforms = [ "aarch64-darwin" ];
    mainProgram = "swift";
  };
}
