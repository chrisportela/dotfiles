{
  upstreamOpenclaw,
}:

let
  version = "2026.4.2";
  tagVersion = "2026.4.2";
in
upstreamOpenclaw.overrideAttrs (
  finalAttrs: prev: {
    inherit version;

    src = prev.src.override {
      tag = "v${tagVersion}";
      hash = "sha256-wVS2OuBNrF1yWjmINxde0kC5mvY2QUUtwYpYrZcARkI=";
    };

    pnpmDepsHash = "sha256-aHepSWiQ4+UyjPHBF+4+M9/nFrgfCw422q671saJM+U=";

    passthru = prev.passthru // {
      updateScript = ./update.sh;
    };

    meta = prev.meta // {
      knownVulnerabilities = [ ];
    };
  }
)
