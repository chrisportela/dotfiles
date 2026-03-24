{
  upstreamOpenclaw,
}:

let
  version = "2026.3.23";
  tagVersion = "2026.3.13-1";
in
upstreamOpenclaw.overrideAttrs (
  finalAttrs: prev: {
    inherit version;

    src = prev.src.override {
      tag = "v${tagVersion}";
      hash = "sha256-oWEYIzrAnYbyyFWFxFCm93i4eprH7hztX+ZHQRpFtQ4=";
    };

    pnpmDepsHash = "sha256-OUPUKDfvKQezDhbpfrKw+4q2qssIVN7eAjS044Z2KJg=";

    passthru = prev.passthru // {
      updateScript = ./openclaw-update.sh;
    };

    meta = prev.meta // {
      knownVulnerabilities = [ ];
    };
  }
)
