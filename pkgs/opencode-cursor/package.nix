{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  bun,
}:

buildNpmPackage (finalAttrs: {
  pname = "opencode-cursor";
  version = "2.4.4-unstable-2026-05-10";

  src = fetchFromGitHub {
    owner = "Nomadcxx";
    repo = "opencode-cursor";
    rev = "c6ebd61236ab83c03fd74e31f7dcc97786852faa";
    hash = "sha256-k5oYLbeC5jZYWePiQkZSALbDeyCHavycnj7Vv2SyVeQ=";
  };

  npmDepsHash = "sha256-emXpL59B9bb2TkgyhFIQdrKOw1RTu7GYXOIvMS9nPa0=";

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
