{
  upstreamOpenclaw,
}:

let
  version = "2026.6.9";
  tagVersion = "2026.6.9";
in
upstreamOpenclaw.overrideAttrs (
  finalAttrs: prev: {
    inherit version;

    src = prev.src.override {
      tag = "v${tagVersion}";
      hash = "sha256-+iKPji3NZzG9kg3j35Qjvm+7WJ9QYOjTuPYF/Kfd26o=";
    };

    pnpmDepsHash = "sha256-qr19mo4czha39Q2PBrYLKxyKjyTq95M9LhYTf2S50q4=";

    passthru = prev.passthru // {
      updateScript = ./update.sh;
    };

    meta = prev.meta // {
      knownVulnerabilities = [ ];
    };
  }
)
