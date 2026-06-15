{
  lib,
  stdenv,
  buildNpmPackage,
  fetchzip,
  autoPatchelfHook,
  versionCheckHook ? null,
  writableTmpDirAsHomeHook ? null,
  bubblewrap ? null,
  procps,
  socat ? null,
}:

let
  version = "2.1.178";

in
buildNpmPackage (finalAttrs: {
  pname = "claude-code";
  inherit version;

  src = fetchzip {
    url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${finalAttrs.version}.tgz";
    hash = "sha256-UM02eJ4IIB+VtzerM8ovWD+cuF6tZDAlJvzW7sWRfKs=";
  };

  npmDepsHash = "sha256-GkYTTeTfS94N2ms6AGWm/hlajf6wtc8c5+2cYLiN3KM=";

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  # npm installs both glibc and musl native binaries; ignore the musl one
  autoPatchelfIgnoreMissingDeps = [ "libc.musl-*" ];

  strictDeps = true;

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  dontNpmBuild = true;

  env.AUTHORIZED = "1";

  postInstall = ''
    # npmInstallHook creates a Node.js shim for bin/claude, but claude-code
    # is now a native binary. Replace the shim with a direct wrapper.
    rm $out/bin/claude
    makeWrapper $out/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe $out/bin/claude \
      --set DISABLE_AUTOUPDATER 1 \
      --set-default FORCE_AUTOUPDATE_PLUGINS 1 \
      --set DISABLE_INSTALLATION_CHECKS 1 \
      --unset DEV \
      --prefix PATH : ${
        lib.makeBinPath (
          [ procps ]
          ++ lib.optionals stdenv.hostPlatform.isLinux (
            lib.optional (bubblewrap != null) bubblewrap ++ lib.optional (socat != null) socat
          )
        )
      }
  '';

  doInstallCheck = versionCheckHook != null && writableTmpDirAsHomeHook != null;
  nativeInstallCheckInputs =
    lib.optionals (versionCheckHook != null && writableTmpDirAsHomeHook != null)
      [
        writableTmpDirAsHomeHook
        versionCheckHook
      ];
  versionCheckKeepEnvironment = [ "HOME" ];
  passthru = {
    updateScript = ./update.sh;
  };

  meta = {
    description = "Agentic coding tool that lives in your terminal, understands your codebase, and helps you code faster";
    homepage = "https://github.com/anthropics/claude-code";
    license = lib.licenses.unfree;
    mainProgram = "claude";
  };
})
