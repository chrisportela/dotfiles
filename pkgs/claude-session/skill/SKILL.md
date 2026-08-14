---
name: session
description: Search and browse past Claude Code sessions. Indexes all session history already stored by Claude Code and makes it searchable by keyword, project, or date. Can also name sessions for easy recall.
triggers:
  - session
  - find session
  - session search
  - search sessions
  - past session
  - name session
  - session name
  - name this session
  - call this session
  - unname session
  - clear session name
---

# Session Tracker Skill

## Usage

```
/session <query>                 # Search sessions by keyword
/session list                    # Show 20 most recent sessions
/session list --all              # Show all sessions
/session show <id>               # Full details (supports partial IDs)
/session name <name>             # Name the most recent session (by last activity)
/session name <id> <name>        # Name a specific session by ID
/session autoname [<id>]         # Generate title from summary + session start time
/session unname [<id>]           # Clear a session's name
/session rebuild                 # Force rebuild the index
/session stats                   # Index statistics by project
```

## How It Works

Claude Code already saves every user message to `~/.claude/history.jsonl` with session IDs, timestamps, and project paths. Session transcripts live as individual JSONL files under `~/.claude/projects/*/`. This skill indexes all of that and makes it searchable.

### Implementation

Entry point: `claude-session <command> [args]`

**CRITICAL OUTPUT RULES — read before running anything:**
1. **Print the FULL command output verbatim, inside a fenced code block.** Wrap ALL output in triple backticks so it renders exactly as-is. Like this:
   ````
   ```
   <raw output here>
   ```
   ````
   Do NOT summarize, paraphrase, truncate, or reformat it. Do NOT shorten session IDs — they are full UUIDs and must be shown in full. The skill handles all formatting. Your only job is to relay what it prints, nothing more.
2. **Do NOT add commentary** after the output. No "What do you need?", no "Here are your sessions:", no interpretation. Just the code block.
3. **Do NOT ask follow-up questions** after `list` or `search`. The output is self-contained.
4. **If the user references an already-shown list** (e.g., "the most recent", "the third one", "that one") — use the IDs already printed in the previous output. Do NOT re-run `list` or `show` unnecessarily.

### Name + summarize requests

If the user asks you to **"name + summarize"** a session, or otherwise wants a generated title based on the session itself:

1. Use `claude-session autoname [<id>]` instead of asking them for a manual title.
2. The generated session name MUST start with the session start timestamp in this exact format: `dd/mm/yy HH:MM`
3. The rest of the title should be a concise summary derived from the session's summary or first bullet.
4. Keep the final title within the existing 50-character limit.

### Naming Sessions

Users name sessions in natural language. They will NEVER type IDs. Your job is to resolve which session they mean.

**How to handle naming requests:**

1. **"Name this session X"** / **"Call this session X"** — Name the most recent session (by last activity). Run: `claude-session name "<name>"`
2. **"Name the session where I worked on the clinic bot"** — First search (`claude-session search "clinic bot"`), identify the right session from results, then name it by ID (`claude-session name <id> "<name>"`). The user never sees or types the ID — you resolve it.
3. **"Name my last session X"** — Run: `claude-session name "<name>"` (defaults to most recent by last activity)
4. **After `/session list`**, user says **"name the third one X"** — You already have the list output with IDs. Use the ID from the third entry.
5. **"Clear the name from X"** / **"Unname the clinic bot session"** — Search to find it, then run: `claude-session unname <id>`. Or `claude-session unname` to clear the most recent.
6. **"Name + summarize this session"** / **"Summarize and title that one"** — Run: `claude-session autoname` (or `claude-session autoname <id>` if the target session is already known)

**Key rules:**
- The user NEVER types or sees session IDs. You handle all ID resolution behind the scenes.
- Names are 1-50 characters. If the user gives something longer, ask them to shorten it.
- Auto-generated names for name+summarize requests MUST include the session start time prefix in `dd/mm/yy HH:MM` format.
- Named sessions show as `Name — summary` in list view and `Name: X` in detail view.
- Names are searchable — `/session search "Vault Reorg"` finds named sessions with highest relevance.
- Names can be cleared with `unname` — this removes the name but preserves the AI summary.
