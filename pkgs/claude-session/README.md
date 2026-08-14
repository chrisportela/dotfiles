# claude-session

CLI + Claude Code skill from
[claude-session-skill](https://github.com/tjp2021/claude-session-skill):
keyword search, browsing, and naming of past Claude Code sessions indexed
from `~/.claude/history.jsonl`.

## How it's packaged

- Built from the **npm tarball**, whose `dist/session.js` is a prebuilt
  self-contained bundle (`bun build --target node`), so it runs under plain
  Node — Bun is not needed.
- One patch (`postPatch`): data dir `~/.claude/skills/session/data` →
  `~/.local/share/claude-session` (the skill dir is a read-only store symlink
  under home-manager).
- `skill/SKILL.md` is a **vendored** copy of upstream's `SKILL.md` with its
  command references rewritten (`bun run …/session.ts` → `claude-session`,
  the wrapper on PATH). It is vendored rather than patched at build time so
  `modules/home/coding-agents.nix` can wire the repo path into
  `programs.claude-code.skills.session` — pointing home-manager at the built
  package would force building it during evaluation (IFD), which breaks
  `nix flake check` and Hydra eval. `update.sh` regenerates it each release.
- The same file is also installed to `$out/share/claude-session/skill/`.
- The upstream MCP server variant is intentionally not installed.

## Optional

`claude-session autoname` uses the Anthropic API for AI summaries and needs
`ANTHROPIC_API_KEY` in the environment; everything else works without it.

## Updating

`./update.sh` (or the repo-wide `nix run .#update`) bumps the version and
tarball hash from the npm registry and regenerates the vendored
`skill/SKILL.md` from the new tarball.
