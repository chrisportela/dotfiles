{
  lib,
  stdenv,
  buildNpmPackage,
  fetchzip,
  versionCheckHook ? null,
  writableTmpDirAsHomeHook ? null,
  bubblewrap ? null,
  procps,
  socat ? null,
}:

let
  version = "2.1.89";

in
buildNpmPackage (finalAttrs: {
  pname = "claude-code";
  inherit version;

  src = fetchzip {
    url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${finalAttrs.version}.tgz";
    hash = "sha256-FoTm6KDr+8Dzhk4ibZUlU1QLPFdPm/OriUUWqAaFswg=";
  };

  npmDepsHash = "sha256-NI4F5bq0lEuMjLUdkGrml2aOzGbGkdyUckgfeVFEe8o=";

  strictDeps = true;

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
    substituteInPlace cli.js \
      --replace-fail '#!/bin/sh' '#!/usr/bin/env sh'
  '';

  dontNpmBuild = true;

  env.AUTHORIZED = "1";

  postInstall = ''
    wrapProgram $out/bin/claude \
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
