{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  bun,
}:

buildNpmPackage (finalAttrs: {
  pname = "opencode-cursor";
  version = "2.3.11";

  src = fetchFromGitHub {
    owner = "Nomadcxx";
    repo = "opencode-cursor";
    rev = "f07940273c21153807234dfbc6ceaeac5b47ad96";
    hash = "sha256-5sGEQAjDVUiNnzSy6Eaq/B3WODC3htnR3ua2JfUmPbU=";
  };

  npmDepsHash = "sha256-3KVxslrcs20ombCHgnZjLqjcXWRkfnQaR2s4u7+yTCU=";

  nativeBuildInputs = [ bun ];

  # We use bun build instead of npm run build
  dontNpmBuild = true;

  buildPhase = ''
    runHook preBuild
    bun build ./src/index.ts ./src/plugin-entry.ts ./src/cli/discover.ts ./src/cli/opencode-cursor.ts \
      --outdir ./dist --target node
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
    #!/bin/sh
    exec sh $share/scripts/sync-models.sh "\$@"
    WRAPPER
    chmod +x $out/bin/opencode-cursor-sync-models

    runHook postInstall
  '';

  passthru.updateScript = ./opencode-cursor-update.sh;

  meta = {
    description = "Use Cursor Pro models in OpenCode via HTTP proxy with OAuth";
    longDescription = ''
      No prompt limits. No broken streams. Full thinking + tool support in OpenCode.
      Your Cursor subscription, properly integrated.
    '';
    homepage = "https://github.com/Nomadcxx/opencode-cursor";
    license = lib.licenses.isc;
    mainProgram = "opencode-cursor-sync-models";
    maintainers = with lib.maintainers; [ chrisportela ];
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
})
