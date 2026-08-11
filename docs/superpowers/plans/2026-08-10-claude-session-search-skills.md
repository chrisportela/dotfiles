# Claude Code Session-Search Skills Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install two Nix-managed Claude Code skills — `claude-history` (Rust CLI, semantic/lexical transcript search) and `claude-session` (session naming/keyword search) — wired into `programs.claude-code.skills` for all coding-agents hosts.

**Architecture:** `claude-history` comes in as a flake input (upstream ships a working `flake.nix`); `claude-session` is a new `pkgs/claude-session/` binary-wrapper package built from the npm tarball's prebuilt Node bundle (no Bun). Both are re-exported as flake packages, injected into `pkgs` via the existing `overlays/default.nix` + `lib/import-pkgs.nix` pattern, and registered as skills in `modules/home/coding-agents.nix`.

**Tech Stack:** Nix flakes, home-manager `programs.claude-code`, npm registry fetchurl, makeWrapper + nodejs.

**Spec:** `docs/superpowers/specs/2026-08-07-claude-session-search-skills-design.md`

## Global Constraints

- Repo root for all paths/commands: the `claude-skills` worktree (`/home/cmp/src/dotfiles/.worktrees/claude-skills`). Never touch main or the repo root checkout.
- New files MUST be `git add`ed before any `nix build` — flake evaluation cannot see untracked files.
- `nix fmt` may rewrite unrelated files with pre-existing drift. Format only the files you changed (`nix fmt <file>...`) and never commit drift in unrelated files.
- Pre-built binary wrappers use `package.nix` (not `default.nix`) per CLAUDE.md.
- Commit messages: short imperative sentence (repo style, no conventional-commit prefixes), ending with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Do NOT use registry `nixpkgs#X` to validate anything about this project (nix-flake-discipline rule). All builds go through `.#<attr>`.
- npm tarball for claude-session v1.1.8: `https://registry.npmjs.org/claude-session-skill/-/claude-session-skill-1.1.8.tgz`, hash `sha256-MSPAlCYYmK8gVlyry4IhvcC7XCGL+0+yk6ylfbbU2xY=` (already prefetched).

---

### Task 1: claude-history flake input + package export

**Files:**
- Modify: `flake.nix` (inputs block ~line 64; packages set ~line 155; hydraJobs.packages ~line 327)
- Modify: `overlays/default.nix` (add overlay entry)
- Modify: `lib/import-pkgs.nix` (add overlay to list ~line 32)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: flake output `packages.<system>.claude-history` and `pkgs.claude-history` (with `.src` = upstream repo source, containing `skills/claude-history/SKILL.md`), available to Task 3.

- [ ] **Step 1: Add the flake input**

In `flake.nix`, after the `android-nixpkgs` input block, add:

```nix
    claude-history = {
      url = "github:raine/claude-history";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
```

(Upstream's flake builds via `nixpkgs.legacyPackages.${system}` with `buildRustPackage`; `follows` is safe. It links `onnxruntime` dynamically — CPU-only default from nixos-unstable, cached.)

- [ ] **Step 2: Export the package**

In `flake.nix` `packages`, after the `context7` line, add:

```nix
              claude-history = inputs.claude-history.packages.${system}.default;
```

In `hydraJobs.packages`, after the `context7.${sys}` line, add:

```nix
              claude-history.${sys} = pkgs.claude-history;
```

- [ ] **Step 3: Add the overlay**

In `overlays/default.nix`, after the `context7` entry, add (simple re-export form, same as `context7`):

```nix
  claude-history = (
    final: prev: {
      claude-history = self.packages.${final.stdenv.system}.claude-history;
    }
  );
```

In `lib/import-pkgs.nix`, add `claude-history` to the overlay name list after `context7`.

- [ ] **Step 4: Lock and build**

```bash
nix flake lock
nix fmt flake.nix overlays/default.nix lib/import-pkgs.nix
git add flake.nix flake.lock overlays/default.nix lib/import-pkgs.nix
nix build .#claude-history
```

Expected: builds successfully (Rust compile; may take a few minutes on first build).

- [ ] **Step 5: Smoke test**

```bash
./result/bin/claude-history --version
./result/bin/claude-history agent search "opencode build" --top 3
ls "$(nix eval --raw .#claude-history.src)/skills/claude-history/"
```

Expected: version prints; agent search returns results from real history (or a clean "no results"); `SKILL.md` listed in the src skills dir.

- [ ] **Step 6: Commit**

```bash
git commit -m "Add claude-history flake input and package export

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

(Only the four staged files; nothing else.)

---

### Task 2: pkgs/claude-session package

**Files:**
- Create: `pkgs/claude-session/package.nix`
- Create: `pkgs/claude-session/update.sh` (executable)
- Create: `pkgs/claude-session/README.md`
- Modify: `flake.nix` (packages + hydraJobs.packages)
- Modify: `overlays/default.nix`, `lib/import-pkgs.nix`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: flake output `packages.<system>.claude-session` and `pkgs.claude-session` providing `bin/claude-session` and skill dir `$out/share/claude-session/skill/` (contains patched `SKILL.md`), used by Task 3.

- [ ] **Step 1: Write `pkgs/claude-session/package.nix`**

```nix
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
```

- [ ] **Step 2: Write `pkgs/claude-session/update.sh`** (then `chmod +x`)

```bash
#!/usr/bin/env nix
#!nix shell --ignore-environment nixpkgs#cacert nixpkgs#bash nixpkgs#curl nixpkgs#nix nixpkgs#gnused nixpkgs#coreutils nixpkgs#jq --command bash

set -euo pipefail

pkg=pkgs/claude-session/package.nix

version=$(curl -s https://registry.npmjs.org/claude-session-skill/latest | jq -r .version)
current=$(sed -nE 's/.*version = "([^"]+)".*/\1/p' "$pkg")
echo "Latest version: $version"
echo "Current version: $current"

if [ "$version" = "$current" ]; then
  echo "Already up to date."
  exit 0
fi

echo "Updating $current -> $version"

url="https://registry.npmjs.org/claude-session-skill/-/claude-session-skill-$version.tgz"
store_path=$(nix-prefetch-url "$url" --name "claude-session-skill-$version.tgz" 2>/dev/null)
hash=$(nix hash convert --to sri --hash-algo sha256 "$store_path")

sed -i "s|version = \"$current\"|version = \"$version\"|" "$pkg"
sed -i "s|hash = \"sha256-[^\"]*\"|hash = \"$hash\"|" "$pkg"

echo "Updated claude-session to $version"
```

- [ ] **Step 3: Write `pkgs/claude-session/README.md`**

```markdown
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
```

- [ ] **Step 4: Wire into flake**

In `flake.nix` `packages`, after the `claude-history` line from Task 1, add:

```nix
              claude-session = pkgs.pkgsUnstable.callPackage ./pkgs/claude-session/package.nix { };
```

In `hydraJobs.packages`, after `claude-history.${sys}`, add:

```nix
              claude-session.${sys} = pkgs.claude-session;
```

In `overlays/default.nix`, after the `claude-history` entry, add:

```nix
  claude-session = (
    final: prev: {
      claude-session = self.packages.${final.stdenv.system}.claude-session;
    }
  );
```

In `lib/import-pkgs.nix`, add `claude-session` to the overlay list after `claude-history`.

- [ ] **Step 5: Build and verify patches**

```bash
nix fmt pkgs/claude-session/package.nix flake.nix overlays/default.nix lib/import-pkgs.nix
git add pkgs/claude-session flake.nix overlays/default.nix lib/import-pkgs.nix
nix build .#claude-session
grep -F -c '"..", ".local", "share", "claude-session")' result/share/claude-session/session.js
grep -q 'bun' result/share/claude-session/skill/SKILL.md && echo "PATCH FAILED" || echo "SKILL.md clean"
head -4 result/share/claude-session/skill/SKILL.md
```

Expected: build succeeds; first grep prints `2` (CLI + MCP copies of `DATA_DIR`); "SKILL.md clean"; head shows the `name: session` frontmatter. If the count is 0, inspect `result/share/claude-session/session.js` around `DATA_DIR` and fix the `substituteInPlace` pattern.

- [ ] **Step 6: Smoke test the CLI**

```bash
./result/bin/claude-session stats
ls ~/.local/share/claude-session/
```

Expected: index builds and per-project stats print; `index.json` exists in the XDG dir; nothing written under `~/.claude/skills/`.

- [ ] **Step 7: Commit**

```bash
git commit -m "Add claude-session package (session search/naming CLI + skill)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Skill wiring in coding-agents.nix + activation

**Files:**
- Modify: `modules/home/coding-agents.nix` (packages list ~line 33-65; `programs.claude-code` block ~line 27-29)

**Interfaces:**
- Consumes: `pkgs.claude-history` (Task 1: binary + `.src` skill dir), `pkgs.claude-session` (Task 2: binary + `$out/share/claude-session/skill`).
- Produces: `~/.claude/skills/claude-history/` and `~/.claude/skills/session/` on all hosts with `chrisportela.coding-agents.enable = true`.

- [ ] **Step 1: Add binaries to home.packages**

In `modules/home/coding-agents.nix`, in the `with pkgs; [ ... ]` list containing `claude-code` and `claude-monitor`, add:

```nix
        claude-history
        claude-session
```

- [ ] **Step 2: Register the skills**

Replace:

```nix
    programs.claude-code = {
      enable = true;
    };
```

with:

```nix
    programs.claude-code = {
      enable = true;
      skills = {
        # Upstream ships the skill without YAML frontmatter, which Claude
        # Code needs for discovery — prepend it and inline the rest.
        claude-history =
          ''
            ---
            name: claude-history
            description: Search and read past Claude Code conversations with the claude-history CLI. Use when the user references a previous session or past conversation, asks what was decided or done before, or wants to find, quote, or resume prior work.
            ---

          ''
          + builtins.readFile "${pkgs.claude-history.src}/skills/claude-history/SKILL.md";
        session = "${pkgs.claude-session}/share/claude-session/skill";
      };
    };
```

- [ ] **Step 3: Build the ada home config**

```bash
nix fmt modules/home/coding-agents.nix
git add modules/home/coding-agents.nix
nix build --no-link '.#homeConfigurations."cmp@ada".activationPackage'
```

Expected: builds. If `builtins.readFile` on `pkgs.claude-history.src` errors (src not a plain source path), fall back to referencing the input via a small overlay entry `claude-history-src = inputs.claude-history;` in `flake.nix`'s inline overlays (next to the `agenix` one) and read from `${pkgs.claude-history-src}/skills/claude-history/SKILL.md`.

- [ ] **Step 4: Build remaining targets**

```bash
nix build --no-link .
nix build --no-link '.#homeConfigurations."cmp@flamme".activationPackage'
```

Expected: both build (flamme exercises a second coding-agents host; `.` is the default cmp config, which has coding-agents disabled and must still evaluate).

- [ ] **Step 5: Activate on ada**

```bash
out=$(nix build --no-link --print-out-paths '.#homeConfigurations."cmp@ada".activationPackage')
HOME_MANAGER_BACKUP_EXT=backup "$out/activate"
```

Expected: activation succeeds (generations are rollback-able via `home-manager generations`).

- [ ] **Step 6: Verify installed skills end-to-end**

```bash
ls -la ~/.claude/skills/
head -5 ~/.claude/skills/claude-history/SKILL.md
grep -m1 'Entry point' ~/.claude/skills/session/SKILL.md
claude-history agent search "opencode build" --top 3
claude-session list | head -n 10
```

Expected: `claude-history` and `session` appear (store symlinks) alongside the pre-existing unmanaged `context7-mcp`; frontmatter starts `--- name: claude-history`; entry-point line says `claude-session <command> [args]`; both CLIs answer from real history.

- [ ] **Step 7: Commit**

```bash
git commit -m "Wire claude-history and claude-session skills into coding-agents

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```
