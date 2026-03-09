{
  lib,
  stdenv,
  fetchFromGitHub,
  perl,
}:

stdenv.mkDerivation rec {
  pname = "cliclick";
  version = "5.1";

  src = fetchFromGitHub {
    owner = "BlueM";
    repo = "cliclick";
    rev = version;
    hash = "sha256-8lWfeRPCF2zn9U79uZkhlj0izGSueTZuYpJx1LgsyfQ=";
  };

  nativeBuildInputs = [ perl ];

  env.NIX_CFLAGS_COMPILE = "-include cliclick_Prefix.pch -I Actions -I .";

  preBuild = ''
    patchShebangs generate-action-classes-macro.sh
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp cliclick $out/bin/
    runHook postInstall
  '';

  meta = with lib; {
    description = "macOS command-line tool for simulating mouse and keyboard events";
    homepage = "https://github.com/BlueM/cliclick";
    license = licenses.bsd3;
    platforms = platforms.darwin;
    mainProgram = "cliclick";
  };
}
