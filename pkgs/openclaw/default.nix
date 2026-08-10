{
  upstreamOpenclaw,
}:

let
  version = "2026.7.1";
  tagVersion = "2026.7.1-2";
in
upstreamOpenclaw.overrideAttrs (
  finalAttrs: prev: {
    inherit version;

    src = prev.src.override {
      tag = "v${tagVersion}";
      hash = "sha256-kpiKCTjXX4l525IJDNsnI7j2IT6ZYdqvFTyRlKGgomg=";
    };

    pnpmDepsHash = "sha256-/ou2Hoix9m/be6kq4Osg4gTTQQRTkL5uLOuERmevuQ0=";

    passthru = prev.passthru // {
      updateScript = ./update.sh;
    };

    meta = prev.meta // {
      knownVulnerabilities = [ ];
    };
  }
)
