{
  upstreamOpenclaw,
}:

let
  version = "2026.6.5";
  tagVersion = "2026.6.5";
in
upstreamOpenclaw.overrideAttrs (
  finalAttrs: prev: {
    inherit version;

    src = prev.src.override {
      tag = "v${tagVersion}";
      hash = "sha256-hiYbIhE13XMFIeB0zmb6AHlfw8le6vpJgCqN81YWGsE=";
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
