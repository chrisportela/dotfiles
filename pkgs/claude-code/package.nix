{
  lib,
  claude-code,
  fetchzip,
}:

let
  version = "2.1.74";
in
let
  base =
    if lib.versionAtLeast claude-code.version version then
      claude-code
    else
      claude-code.overrideAttrs (
        finalAttrs: prev: {
          inherit version;

          src = fetchzip {
            url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${finalAttrs.version}.tgz";
            hash = "sha256-74xAW5sc3l5SH7UUFsUVpK6A6gTPn4fGg+c51MsXXhE=";
          };

          npmDepsHash = "sha256-FQEQQK8UIvPw8WMYGW+X7TPAWi+SVJEhUV0MqO2gQz0=";

          postPatch = ''
            cp ${./package-lock.json} package-lock.json
            substituteInPlace cli.js \
              --replace-fail '#!/bin/sh' '#!/usr/bin/env sh'
          '';
        }
      );
in
base.overrideAttrs (prev: {
  passthru = prev.passthru // {
    updateScript = ./update.sh;
  };
})
