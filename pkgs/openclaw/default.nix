{
  upstreamOpenclaw,
}:

let
  version = "2026.3.28";
  tagVersion = "2026.3.28";
in
upstreamOpenclaw.overrideAttrs (
  finalAttrs: prev: {
    inherit version;

    src = prev.src.override {
      tag = "v${tagVersion}";
      hash = "sha256-mv1G9AWo/aGrJZGLE5mbvQrJDEgfvuvBlDBfi7EPnbc=";
    };

    pnpmDepsHash = "sha256-yT7qQ3rMqVaafbeY8VeUcvlx6dedmVxEm70M35iTXOQ=";

    passthru = prev.passthru // {
      updateScript = ./update.sh;
    };

    meta = prev.meta // {
      knownVulnerabilities = [ ];
    };
  }
)
