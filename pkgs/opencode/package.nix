{
  upstreamOpencode,
}:

let
  version = "1.14.19";
in
upstreamOpencode.overrideAttrs (
  finalAttrs: prev: {
    inherit version;

    src = prev.src.override {
      tag = "v${version}";
      hash = "sha256-kKFqMf+l+V1kaf6bZtKfUSRYYjKc3VNgxlxic2fM2fo=";
    };

    node_modules = prev.node_modules.overrideAttrs {
      inherit (finalAttrs) version src;
      outputHash = "sha256-RYyYp7LXMZP8RWZps1Esu8tW/rBM30QbH9Qrwi00adI=";
    };

    passthru = prev.passthru // {
      updateScript = ./update.sh;
    };
  }
)
