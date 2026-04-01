{
  upstreamOpenclaw,
}:

let
  version = "2026.4.1";
  tagVersion = "2026.4.1";
in
upstreamOpenclaw.overrideAttrs (
  finalAttrs: prev: {
    inherit version;

    src = prev.src.override {
      tag = "v${tagVersion}";
      hash = "sha256-nQmR98XsEcm8HQHUpb2WB9r/OFJhjycj1ieXbsRO9Cs=";
    };

    pnpmDepsHash = "sha256-Aiuoff4yDI0GUgu/RzUQ/WXUOcf+AByyathBTVCofI8=";

    passthru = prev.passthru // {
      updateScript = ./update.sh;
    };

    meta = prev.meta // {
      knownVulnerabilities = [ ];
    };
  }
)
