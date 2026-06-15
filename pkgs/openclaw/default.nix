{
  upstreamOpenclaw,
}:

let
  version = "2026.6.6";
  tagVersion = "2026.6.6";
in
upstreamOpenclaw.overrideAttrs (
  finalAttrs: prev: {
    inherit version;

    src = prev.src.override {
      tag = "v${tagVersion}";
      hash = "sha256-sgLyNHQNnuEWZBaIxqJUz9o0x+P1EgNuLlUfy1iRunk=";
    };

    pnpmDepsHash = "sha256-eADEHT4CW8ffCKwEfQjjrQ63oZQUYmRYymYQpMT8/gY=";

    passthru = prev.passthru // {
      updateScript = ./update.sh;
    };

    meta = prev.meta // {
      knownVulnerabilities = [ ];
    };
  }
)
