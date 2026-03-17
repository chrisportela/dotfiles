{
  lib,
  openclaw,
}:

let
  version = "2026.3.13-1";
in
let
  base =
    if lib.versionAtLeast openclaw.version version then
      openclaw
    else
      openclaw.overrideAttrs (
        finalAttrs: prev: {
          inherit version;

          src = prev.src.override {
            tag = "v${finalAttrs.version}";
            hash = "sha256-OUPUKDfvKQezDhbpfrKw+4q2qssIVN7eAjS044Z2KJg=";
          };

          pnpmDepsHash = "sha256-p6Lfpo5X9epJInKhcpRutIktnsou5TAptyI/Q/Wwqz4=";
        }
      );
in
base.overrideAttrs (prev: {
  meta = prev.meta // {
    knownVulnerabilities = [ ];
  };
  passthru = prev.passthru // {
    updateScript = ./openclaw-update.sh;
  };
})
