{
  upstreamOpenclaw,
}:

let
  version = "2026.5.27";
  tagVersion = "2026.5.27";
in
upstreamOpenclaw.overrideAttrs (
  finalAttrs: prev: {
    inherit version;

    src = prev.src.override {
      tag = "v${tagVersion}";
      hash = "sha256-jshgsxnnVXL5TcjeIfR+GiA3W5UBkSIH2jGtm8SD264=";
    };

    pnpmDepsHash = "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=";

    passthru = prev.passthru // {
      updateScript = ./update.sh;
    };

    meta = prev.meta // {
      knownVulnerabilities = [ ];
    };
  }
)
