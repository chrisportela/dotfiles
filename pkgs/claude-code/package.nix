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
  # Callers can pass the upstream nixpkgs claude-code for version comparison.
  # Named to avoid callPackage auto-filling from pkgs.claude-code, which would
  # cause infinite recursion when this package IS pkgs.claude-code via an overlay.
  upstreamClaudeCode ? null,
}:

let
  version = "2.1.74";

  fromSource = buildNpmPackage (finalAttrs: {
    pname = "claude-code";
    inherit version;

    src = fetchzip {
      url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${finalAttrs.version}.tgz";
      hash = "sha256-74xAW5sc3l5SH7UUFsUVpK6A6gTPn4fGg+c51MsXXhE=";
    };

    npmDepsHash = "sha256-FQEQQK8UIvPw8WMYGW+X7TPAWi+SVJEhUV0MqO2gQz0=";

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

    meta = {
      description = "Agentic coding tool that lives in your terminal, understands your codebase, and helps you code faster";
      homepage = "https://github.com/anthropics/claude-code";
      license = lib.licenses.unfree;
      mainProgram = "claude";
    };
  });

  base =
    if upstreamClaudeCode != null && lib.versionAtLeast upstreamClaudeCode.version version then
      upstreamClaudeCode
    else
      fromSource;
in
base.overrideAttrs (prev: {
  passthru = (prev.passthru or { }) // {
    updateScript = ./update.sh;
  };
})
