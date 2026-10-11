{
  lib,
  rustPlatform,
  fetchzip,
  makeWrapper,
  uv,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "prime-agent";
  version = "0.10.0";

  # The release's -src tarball, not the git tree: the bundled model/MCP
  # catalogs (models.bundled.json, mcp-services.bundled.json) only exist in
  # this asset. It is flat (no top-level directory) and only published for
  # stable releases.
  src = fetchzip {
    url = "https://github.com/PrimeIntellect-ai/prime-agent/releases/download/v${finalAttrs.version}/prime-agent-${finalAttrs.version}-src.tar.gz";
    stripRoot = false;
    hash = "sha256-zBKU50BvkGUWqTSTQlccyodmEoXgyt3iResMpRtNOnQ=";
  };

  cargoHash = "sha256-9WPwC4V2SMqCAedx/OKnMWFzRbjs4bq24VuuVnLr4gI=";

  # The kernel bootstrap runs `uv python install 3.11` before `uv venv
  # --python 3.11`. venv alone installs the same managed Python on demand, so
  # dropping the explicit step changes nothing on a normal system, and lets
  # the NixOS module disable uv's Python downloads (`python-downloads =
  # "never"` makes `uv python install` exit 1) in favour of nixpkgs Pythons.
  patches = [ ./skip-uv-python-install.patch ];

  nativeBuildInputs = [ makeWrapper ];

  cargoBuildFlags = [
    "--bin"
    "prime-agent"
  ];

  # The workspace suite needs tmux, uv with network access and spawns daemons.
  doCheck = false;

  # Same layout as upstream's Homebrew formula: the binary resolves its
  # package directory from current_exe() (following symlinks) and expects the
  # runtime, skills and bundled catalogs beside it. The wrapper therefore
  # execs the real file in libexec/ rather than renaming it with wrapProgram,
  # which would also hide it from the daemon's "prime-agent" process-name
  # matching.
  postInstall = ''
    libexec=$out/libexec/prime-agent
    mkdir -p $libexec
    mv $out/bin/prime-agent $libexec/prime-agent
    cp -r prime-agent-runtime skills $libexec/
    cp models.bundled.json mcp-services.bundled.json LICENSE README.md $libexec/

    # uv is a hard runtime dependency (kernel venv bootstrap). Suffixed so a
    # project devShell's or the user's own uv wins. Self-update cannot work in
    # /nix/store, and upstream's product telemetry is off by default
    # (DO_NOT_TRACK=0 turns it back on).
    makeWrapper $libexec/prime-agent $out/bin/prime-agent \
      --suffix PATH : ${lib.makeBinPath [ uv ]} \
      --set-default PI_SKIP_VERSION_CHECK 1 \
      --set-default DO_NOT_TRACK 1
  '';

  passthru.updateScript = ./update.sh;

  meta = {
    description = "RLM coding agent harness with a persistent Python control environment";
    homepage = "https://github.com/PrimeIntellect-ai/prime-agent";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    mainProgram = "prime-agent";
  };
})
