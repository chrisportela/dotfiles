{
  upstreamOpenclaw,
}:

let
  version = "2026.4.20";
  tagVersion = "2026.4.20";
in
upstreamOpenclaw.overrideAttrs (
  finalAttrs: prev: {
    inherit version;

    src = prev.src.override {
      tag = "v${tagVersion}";
      hash = "sha256-NW2Rr5/JeLnxEsjTBeOdNlUxM26qlJ+4X2GFw+bIGlM=";
    };

    pnpmDepsHash = "sha256-FDajXHs4s0+QDRPq4ZxQWWW9rqeSJVYACAl/5Mw2Agc=";

    passthru = prev.passthru // {
      updateScript = ./update.sh;
    };

    meta = prev.meta // {
      knownVulnerabilities = [ ];
    };
  }
)
