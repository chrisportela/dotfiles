{
  upstreamOpenclaw,
}:

let
  version = "2026.6.10";
  tagVersion = "2026.6.10";
in
upstreamOpenclaw.overrideAttrs (
  finalAttrs: prev: {
    inherit version;

    src = prev.src.override {
      tag = "v${tagVersion}";
      hash = "sha256-X5fj8EcVTksEvbFJz9YeYPzX0PjRf0kmGwsdk0sbOmg=";
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
