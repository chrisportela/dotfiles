# Claude Code session-search skills: claude-history + claude-session

**Date:** 2026-08-07
**Status:** Approved

## Goal

Make past Claude Code sessions searchable and usable from within current
sessions, on all hosts, by installing two skills (plus their backing CLIs)
fully Nix-managed:

- [raine/claude-history](https://github.com/raine/claude-history) — Rust CLI
  with fuzzy/semantic/hybrid search over `~/.claude/projects` transcripts, a
  human TUI, and an `agent` subcommand family (`search`, `read`, `outline`,
  `within`) designed for skill use. Ships a companion skill in
  `skills/claude-history/`.
- [tjp2021/claude-session-skill](https://github.com/tjp2021/claude-session-skill)
  — TypeScript CLI that indexes `~/.claude/history.jsonl` for keyword search,
  session naming, and (optional, API-key-gated) AI summaries. Published to npm
  with a prebuilt self-contained `dist/session.js` (Node target, dependencies
  bundled), so Bun is NOT needed at runtime.

Both were requested despite search overlap: claude-history for strong
search/read, claude-session for naming and summaries.

## Components

### 1. claude-history via flake input

- Add `inputs.claude-history.url = "github:raine/claude-history"` with
  `inputs.nixpkgs.follows = "nixpkgs"` to `flake.nix`.
- Re-export its default package under this flake's `packages.<system>` (so
  `nix build .#claude-history` works) per the repo's package conventions.
- Update path: `nix flake update claude-history`. No cargoHash/update.sh to
  maintain; upstream CI builds with Nix.

### 2. claude-session via `pkgs/claude-session/`

- `package.nix` (pre-built binary wrapper convention): fetch the npm tarball
  for `claude-session-skill`, install `dist/session.js`, wrap with Node as
  `claude-session` on PATH.
- Patches (`substituteInPlace` on the bundle and SKILL.md):
  - Data dir `~/.claude/skills/session/data` → `~/.local/share/claude-session`
    so the skill functions with a read-only store-managed skill directory.
  - `SKILL.md`: `bun run ~/.claude/skills/session/session.ts …` →
    `claude-session …`.
- `update.sh` following the `pkgs/cursor-agent/update.sh` canonical pattern.
- README.md per module/package convention.
- The MCP server variant (`claude-session-mcp`) is NOT installed — the skill
  CLI covers the use case.

### 3. Wiring in `modules/home/coding-agents.nix`

- Add `claude-history` and `claude-session` to `home.packages` (gated on the
  existing `chrisportela.coding-agents.enable`).
- Register both skills via `programs.claude-code.skills`:
  - `claude-history` → `${claude-history.src or package}/…/skills/claude-history`
    (exact source path resolved at implementation).
  - `session` → the patched `SKILL.md` directory from `pkgs/claude-session`.

## Runtime behavior / error handling

- claude-history semantic search downloads a local embedding model on first
  use; no API key, no network config needed in Nix.
- claude-session `autoname` summaries require `ANTHROPIC_API_KEY`; without it
  the feature degrades gracefully. No secret wiring in this change.
- Both tools only read Claude Code's own local state (`~/.claude/history.jsonl`,
  `~/.claude/projects/`); claude-session writes its index to the patched XDG
  data dir.

## Verification

1. `nix build .#claude-session` and `nix build .#claude-history`.
2. `nix build .` (full home config).
3. Runtime smoke: `claude-history agent search "opencode build"`,
   `claude-session rebuild && claude-session list`.
4. Confirm both skills appear under `~/.claude/skills/` after
   `nix run . -- -b backup`, and that the session skill's SKILL.md references
   `claude-session`, not `bun`.
