{
  lib,
  openclaw,
}:

let
  version = "2026.3.11";
in
let
  base =
    if lib.versionAtLeast openclaw.version version then
      openclaw
    else
      openclaw.overrideAttrs (finalAttrs: prev: {
        inherit version;

        src = prev.src.override {
          tag = "v${finalAttrs.version}";
          hash = "sha256-wsbuMKROlL/jqp7RZH6cLdn4H6yc4QmjWc01rsLbGlQ=";
        };

        pnpmDepsHash = "sha256-YnMjA0pD5X4pXU3A7Yab2U9RJ8g31i98S+atGk8J3CQ=";
      });
in
base.overrideAttrs (prev: {
  meta = prev.meta // {
    knownVulnerabilities = [ ];
  };
  passthru = prev.passthru // {
    updateScript = ./openclaw-update.sh;
  };
})
