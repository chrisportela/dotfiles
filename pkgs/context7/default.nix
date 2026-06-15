{
  lib,
  stdenv,
  nodejs,
  pnpm_10,
  fetchPnpmDeps,
  pnpmConfigHook,
  fetchFromGitHub,
  makeWrapper,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "context7";
  version = "3.2.1";

  src = fetchFromGitHub {
    owner = "upstash";
    repo = "context7";
    rev = "ecea65a3e6c54f14e70e03f7eacaed2e580518a8";
    hash = "sha256-Gf3GnVOceAMzsc1SYGQVriDzDD/dQYSoBSrCuQ5M4UI=";
  };

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs)
      pname
      version
      src
      ;
    pnpm = pnpm_10;
    fetcherVersion = 3;
    hash = "sha256-S+TCwe4FJHjSLTUL/cPh+eRtWx/z7REUyfMNT0BgK7k=";
  };

  nativeBuildInputs = [
    nodejs
    pnpmConfigHook
    pnpm_10
    makeWrapper
  ];

  buildPhase = ''
    runHook preBuild

    pnpm --filter "@upstash/context7-mcp..." build
    pnpm --filter "ctx7..." build

    runHook postBuild
  '';

  # pnpm needs this to reinstall prod deps
  env.CI = true;

  installPhase = ''
    runHook preInstall

    # Reinstall with only production deps in hoisted layout
    rm -rf node_modules packages/*/node_modules
    pnpm config set nodeLinker hoisted
    pnpm config set preferSymlinkedExecutables false
    pnpm --filter="@upstash/context7-mcp..." --filter="ctx7..." --offline --prod install

    mkdir -p $out/lib/context7 $out/bin

    # Copy monorepo structure needed for module resolution
    cp -r --reflink=auto node_modules $out/lib/context7/
    cp package.json $out/lib/context7/
    for pkg in mcp cli; do
      mkdir -p $out/lib/context7/packages/$pkg
      cp -r --reflink=auto packages/$pkg/dist packages/$pkg/package.json $out/lib/context7/packages/$pkg/
      if [ -d packages/$pkg/node_modules ]; then
        cp -r --reflink=auto packages/$pkg/node_modules $out/lib/context7/packages/$pkg/
      fi
    done

    makeWrapper ${nodejs}/bin/node $out/bin/context7-mcp \
      --add-flags $out/lib/context7/packages/mcp/dist/index.js
    makeWrapper ${nodejs}/bin/node $out/bin/ctx7 \
      --add-flags $out/lib/context7/packages/cli/dist/index.js

    runHook postInstall
  '';

  passthru.updateScript = ./update.sh;

  meta = {
    description = "Up-to-date code documentation for LLMs — MCP server and CLI";
    homepage = "https://github.com/upstash/context7";
    license = lib.licenses.mit;
    mainProgram = "context7-mcp";
    platforms = lib.platforms.unix;
  };
})
