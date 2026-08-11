# claude-session

CLI + Claude Code skill from
[claude-session-skill](https://github.com/tjp2021/claude-session-skill):
keyword search, browsing, and naming of past Claude Code sessions indexed
from `~/.claude/history.jsonl`.

## How it's packaged

- Built from the **npm tarball**, whose `dist/session.js` is a prebuilt
  self-contained bundle (`bun build --target node`), so it runs under plain
  Node — Bun is not needed.
- Two patches (`postPatch`):
  - Data dir `~/.claude/skills/session/data` → `~/.local/share/claude-session`
    (the skill dir is a read-only store symlink under home-manager).
  - `SKILL.md` command references `bun run …/session.ts` → `claude-session`
    (the wrapper on PATH).
- The patched skill lives at `$out/share/claude-session/skill/` and is wired
  into `programs.claude-code.skills.session` by
  `modules/home/coding-agents.nix`.
- The upstream MCP server variant is intentionally not installed.

## Optional

`claude-session autoname` uses the Anthropic API for AI summaries and needs
`ANTHROPIC_API_KEY` in the environment; everything else works without it.

## Updating

`./update.sh` (or the repo-wide `nix run .#update`) bumps the version and
tarball hash from the npm registry.
