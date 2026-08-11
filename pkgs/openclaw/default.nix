{
  upstreamOpenclaw,
}:

let
  version = "2026.7.1";
  tagVersion = "2026.7.1-2";
in
upstreamOpenclaw.overrideAttrs (
  finalAttrs: prev: {
    inherit version;

    src = prev.src.override {
      tag = "v${tagVersion}";
      hash = "sha256-kpiKCTjXX4l525IJDNsnI7j2IT6ZYdqvFTyRlKGgomg=";
    };

    pnpmDepsHash = "sha256-/ou2Hoix9m/be6kq4Osg4gTTQQRTkL5uLOuERmevuQ0=";

    # 2026.7.x splits @openclaw/ai (and friends) into pnpm workspace packages
    # under packages/; node_modules/@openclaw/ai is a relative symlink into it,
    # so the workspace sources must be present in the output for the CLI to run.
    postInstall = ''
      cp --reflink=auto -r packages $libdir/
      find $libdir/packages -type l -lname "$NIX_BUILD_TOP/*" -delete
      find $libdir/packages -xtype l -delete
    ''
    + prev.postInstall;

    passthru = prev.passthru // {
      updateScript = ./update.sh;
    };

    meta = prev.meta // {
      knownVulnerabilities = [ ];
    };
  }
)
