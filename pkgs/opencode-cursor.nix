{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  bun,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "opencode-cursor";
  version = "2.3.11";

  src = fetchFromGitHub {
    owner = "Nomadcxx";
    repo = "opencode-cursor";
    rev = "f07940273c21153807234dfbc6ceaeac5b47ad96";
    hash = "sha256-5sGEQAjDVUiNnzSy6Eaq/B3WODC3htnR3ua2JfUmPbU=";
  };

  nativeBuildInputs = [ bun ];

  buildPhase = ''
    runHook preBuild

    bun install
    bun run build

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    share=$out/share/opencode-cursor
    mkdir -p $share $out/bin

    cp -r dist $share/
    mkdir -p $share/scripts
    cp scripts/sync-models.sh $share/scripts/
    chmod +x $share/scripts/sync-models.sh

    # Wrapper for sync-models: requires cursor-agent and python3 on PATH at runtime
    cat > $out/bin/opencode-cursor-sync-models << WRAPPER
    #!${stdenvNoCC.shell}
    exec ${stdenvNoCC.shell} $share/scripts/sync-models.sh "\$@"
    WRAPPER
    chmod +x $out/bin/opencode-cursor-sync-models

    runHook postInstall
  '';

  meta = {
    description = "Use Cursor Pro models in OpenCode via HTTP proxy with OAuth";
    longDescription = ''
      No prompt limits. No broken streams. Full thinking + tool support in OpenCode.
      Your Cursor subscription, properly integrated.
    '';
    homepage = "https://github.com/Nomadcxx/opencode-cursor";
    license = lib.licenses.bsd3;
    mainProgram = "opencode-cursor-sync-models";
    maintainers = with lib.maintainers; [ chrisportela ];
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
})
