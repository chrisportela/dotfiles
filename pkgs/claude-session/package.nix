{
  lib,
  fetchurl,
  stdenvNoCC,
  nodejs,
  makeWrapper,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "claude-session";
  version = "1.1.8";

  src = fetchurl {
    url = "https://registry.npmjs.org/claude-session-skill/-/claude-session-skill-${finalAttrs.version}.tgz";
    hash = "sha256-MSPAlCYYmK8gVlyry4IhvcC7XCGL+0+yk6ylfbbU2xY=";
  };

  nativeBuildInputs = [ makeWrapper ];

  postPatch = ''
    # Upstream writes its index into its own skill directory
    # (~/.claude/skills/session/data), which is a read-only store symlink
    # under home-manager. Redirect to XDG data; path.join() collapses the
    # "..". The literal appears twice in the bundle (CLI + MCP copies).
    substituteInPlace dist/session.js \
      --replace-fail '"skills", "session", "data")' '"..", ".local", "share", "claude-session")'

    # The skill must invoke the wrapped CLI on PATH, not bun against a
    # writable checkout.
    substituteInPlace SKILL.md \
      --replace-fail 'bun run ~/.claude/skills/session/session.ts' 'claude-session'
    sed -i 's/session\.ts/claude-session/g' SKILL.md
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share/claude-session/skill
    cp dist/session.js $out/share/claude-session/session.js
    cp SKILL.md $out/share/claude-session/skill/SKILL.md

    makeWrapper ${lib.getExe nodejs} $out/bin/claude-session \
      --add-flags "$out/share/claude-session/session.js"

    runHook postInstall
  '';

  passthru.updateScript = ./update.sh;

  meta = {
    description = "Search, browse, and name past Claude Code sessions (claude-session-skill CLI + skill)";
    homepage = "https://github.com/tjp2021/claude-session-skill";
    license = lib.licenses.mit;
    mainProgram = "claude-session";
    platforms = lib.platforms.all;
  };
})
