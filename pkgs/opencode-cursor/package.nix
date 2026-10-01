{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  bun,
}:

buildNpmPackage (finalAttrs: {
  pname = "opencode-cursor";
  version = "2.5.9-unstable-2026-09-29";

  src = fetchFromGitHub {
    owner = "Nomadcxx";
    repo = "opencode-cursor";
    rev = "97785008b5fdb3716a50f52b86f13e9e4413541f";
    hash = "sha256-WQcGO+neN/O8zS86a/zG6LPTeR8nm53F8PGYVEGurR0=";
  };

  npmDepsHash = "sha256-JsOgzeWuVCb6pN/AF/PT6U+Wu+nVicC4ocFSNsohPA8=";

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

  passthru.updateScript = ./update.sh;

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
