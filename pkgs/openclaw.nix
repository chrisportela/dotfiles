{
  upstreamOpenclaw,
}:

let
  version = "2026.3.13-1";
in
upstreamOpenclaw.overrideAttrs (
  finalAttrs: prev: {
    inherit version;

    src = prev.src.override {
      tag = "v${finalAttrs.version}";
      hash = "sha256-OUPUKDfvKQezDhbpfrKw+4q2qssIVN7eAjS044Z2KJg=";
    };

    pnpmDepsHash = "sha256-p6Lfpo5X9epJInKhcpRutIktnsou5TAptyI/Q/Wwqz4=";

    passthru = prev.passthru // {
      updateScript = ./openclaw-update.sh;
    };

    meta = prev.meta // {
      knownVulnerabilities = [ ];
    };
  }
)
