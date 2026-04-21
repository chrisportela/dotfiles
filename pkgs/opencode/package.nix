{
  upstreamOpencode,
}:

let
  version = "1.14.20";
in
upstreamOpencode.overrideAttrs (
  finalAttrs: prev: {
    inherit version;

    src = prev.src.override {
      tag = "v${version}";
      hash = "sha256-9nxxvCkeTW3MasXaOhWaQqxqJeq9Q1+5TGULITjhV2Q=";
    };

    node_modules = prev.node_modules.overrideAttrs {
      inherit (finalAttrs) version src;
      outputHash = "sha256-H/bwSUhR9TUx/R/j2ak3c87RvvhvHdrGN5tdf7lAz6I=";
    };

    passthru = prev.passthru // {
      updateScript = ./update.sh;
    };
  }
)
