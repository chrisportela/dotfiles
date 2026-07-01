{
  upstreamOpenclaw,
}:

let
  version = "2026.6.11";
  tagVersion = "2026.6.11";
in
upstreamOpenclaw.overrideAttrs (
  finalAttrs: prev: {
    inherit version;

    src = prev.src.override {
      tag = "v${tagVersion}";
      hash = "sha256-Ryj+aJ4Daql/ILs3Z/Gi+ltBGQfOdtXKJoOqr3YNoQ0=";
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
