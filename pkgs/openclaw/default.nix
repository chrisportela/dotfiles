{
  upstreamOpenclaw,
}:

let
  version = "2026.6.1";
  tagVersion = "2026.6.1";
in
upstreamOpenclaw.overrideAttrs (
  finalAttrs: prev: {
    inherit version;

    src = prev.src.override {
      tag = "v${tagVersion}";
      hash = "sha256-FjxiI7YHkt6fTzJD7G5A3/wsbcWgpO44IHMOwymDxpg=";
    };

    pnpmDepsHash = "sha256-7RQJAVWqhauG8JrF8AD1VU1IJRM+SH05aHAfmFaXraU=";

    passthru = prev.passthru // {
      updateScript = ./update.sh;
    };

    meta = prev.meta // {
      knownVulnerabilities = [ ];
    };
  }
)
