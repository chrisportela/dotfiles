//! tmux automation: a window (or detached session) per worktree with two
//! titled panes — "claude" with the agent command typed but NOT entered, and
//! "shell".
//!
//! Learned from perviewerr: target panes/windows by immutable %id/@id (never
//! by index — pane-base-index varies per config); WT_TMUX_SOCKET routes every
//! call to a private `-L` server so tests are hermetic; and send-keys races
//! shell init (p10k instant-prompt can eat queued keys), so we poll for a
//! drawn prompt before typing.

use std::path::Path;
use std::time::{Duration, Instant};

use anyhow::{Result, bail};

use crate::cmd::Runner;
use crate::setup::on_path;

const READY_SHELLS: &[&str] = &["sh", "ash", "dash", "bash", "zsh", "fish", "nu", "busybox"];

pub struct Tmux {
    socket: Option<String>,
}

impl Tmux {
    pub fn from_env() -> Self {
        Self {
            socket: std::env::var("WT_TMUX_SOCKET")
                .ok()
                .filter(|s| !s.is_empty()),
        }
    }

    /// Window mode requires being inside tmux. The test socket override
    /// counts, so hermetic tests can exercise window mode without a client.
    pub fn inside_tmux(&self) -> bool {
        self.socket.is_some() || std::env::var_os("TMUX").is_some_and(|v| !v.is_empty())
    }

    fn argv<'a>(&'a self, args: &'a [&'a str]) -> Vec<&'a str> {
        let mut v = Vec::with_capacity(args.len() + 2);
        if let Some(sock) = &self.socket {
            v.push("-L");
            v.push(sock.as_str());
        }
        v.extend_from_slice(args);
        v
    }

    fn run(&self, r: &Runner, step: &str, args: &[&str]) -> Result<String> {
        r.run(step, "tmux", &self.argv(args), None)
    }

    fn query(&self, r: &Runner, step: &str, args: &[&str]) -> Result<String> {
        r.query(step, "tmux", &self.argv(args), None)
    }

    /// The session wt should work in. `display-message` resolves the caller's
    /// session via $TMUX; without any client (hermetic tests, no terminal)
    /// tmux's "current session" inference is unreliable, so fall back to the
    /// first listed session.
    pub fn current_session(&self, r: &Runner) -> Option<String> {
        if let Ok(out) = self.query(
            r,
            "current session",
            &["display-message", "-p", "#{session_name}"],
        ) && !out.trim().is_empty()
        {
            return Some(out.trim().to_string());
        }
        let out = self
            .query(
                r,
                "list sessions",
                &["list-sessions", "-F", "#{session_name}"],
            )
            .ok()?;
        out.lines().next().map(str::to_string)
    }

    /// @window_id of the exactly-named window in `session`.
    ///
    /// Space separator, not tab: some tmux versions sanitize control
    /// characters (tabs included) to `_` when output is not a terminal, and
    /// git branch names can never contain spaces, so `split_once(' ')` is
    /// unambiguous.
    pub fn window_named(&self, r: &Runner, session: &str, name: &str) -> Option<String> {
        let out = self
            .query(
                r,
                "list windows",
                &[
                    "list-windows",
                    "-t",
                    &format!("={session}:"),
                    "-F",
                    "#{window_id} #{window_name}",
                ],
            )
            .ok()?;
        out.lines()
            .filter_map(|l| l.split_once(' '))
            .find(|(_, n)| *n == name)
            .map(|(id, _)| id.to_string())
    }

    pub fn kill_window(&self, r: &Runner, window_id: &str) -> Result<()> {
        self.run(r, "kill window", &["kill-window", "-t", window_id])?;
        Ok(())
    }

    fn has_session(&self, r: &Runner, name: &str) -> bool {
        self.query(
            r,
            "check session",
            &["has-session", "-t", &format!("={name}")],
        )
        .is_ok()
    }
}

/// tmux session names cannot contain ':' or '.'; slashes confuse target
/// resolution. Branch names keep them — session names get '-' instead.
pub fn sanitize_session_name(branch: &str) -> String {
    branch
        .chars()
        .map(|c| if matches!(c, '.' | ':' | '/') { '-' } else { c })
        .collect()
}

/// Entry point from `wt add`.
pub fn open_workspace(r: &Runner, branch: &str, wt_path: &Path, want_session: bool) -> Result<()> {
    let t = Tmux::from_env();
    let cwd = wt_path.display().to_string();

    let window_id = if want_session {
        if !on_path("tmux") {
            println!("note: tmux not found — skipping session creation");
            return Ok(());
        }
        let name = sanitize_session_name(branch);
        if t.has_session(r, &name) {
            println!("tmux session '{name}' already exists");
            println!("  tmux attach -t {name}");
            return Ok(());
        }
        let id = t.run(
            r,
            "create session",
            &[
                "new-session",
                "-d",
                "-s",
                &name,
                "-n",
                branch,
                "-c",
                &cwd,
                "-P",
                "-F",
                "#{window_id}",
            ],
        )?;
        println!("Created detached tmux session '{name}'");
        println!("  tmux attach -t {name}");
        id.trim().to_string()
    } else {
        if !t.inside_tmux() {
            println!(
                "note: not inside tmux — skipping window creation (use --session for a detached session)"
            );
            return Ok(());
        }
        let Some(session) = t.current_session(r) else {
            println!("note: could not resolve the current tmux session — skipping window creation");
            return Ok(());
        };
        if let Some(existing) = t.window_named(r, &session, branch) {
            println!("tmux window '{branch}' already exists — selecting it");
            t.run(r, "select window", &["select-window", "-t", &existing])?;
            return Ok(());
        }
        let id = t.run(
            r,
            "create window",
            &[
                "new-window",
                "-a",
                "-d",
                "-t",
                &format!("={session}:"),
                "-n",
                branch,
                "-c",
                &cwd,
                "-P",
                "-F",
                "#{window_id}",
            ],
        )?;
        id.trim().to_string()
    };

    t.run(
        r,
        "split window",
        &["split-window", "-d", "-h", "-t", &window_id, "-c", &cwd],
    )?;
    let panes: Vec<String> = if r.dry_run {
        // The window doesn't exist under dry-run; plan with placeholders.
        vec!["<claude-pane>".into(), "<shell-pane>".into()]
    } else {
        let out = t.query(
            r,
            "list panes",
            &["list-panes", "-t", &window_id, "-F", "#{pane_id}"],
        )?;
        out.lines().map(str::to_string).collect()
    };
    let [claude_pane, shell_pane] = panes.as_slice() else {
        bail!("expected 2 panes in new window, found {}", panes.len());
    };
    for (pane, title) in [(claude_pane, "claude"), (shell_pane, "shell")] {
        // Otherwise the shell's OSC title escape (PS1/precmd) overwrites the
        // pane title on the next prompt draw.
        t.run(
            r,
            "lock pane title",
            &["set-option", "-p", "-t", pane, "allow-set-title", "off"],
        )?;
        t.run(r, "title pane", &["select-pane", "-t", pane, "-T", title])?;
    }

    type_unentered(
        r,
        &t,
        claude_pane,
        "claude",
        Duration::from_secs(5),
        Duration::from_millis(100),
    )?;

    if !want_session {
        t.run(r, "select window", &["select-window", "-t", &window_id])?;
        println!("Opened tmux window '{branch}' (panes: claude, shell)");
    }
    Ok(())
}

/// Type `text` into the pane without pressing Enter. Waits until the pane is
/// running a shell AND has drawn a prompt — send-keys during zsh/p10k init
/// gets eaten or garbled. On timeout, types anyway with a warning.
fn type_unentered(
    r: &Runner,
    t: &Tmux,
    pane: &str,
    text: &str,
    deadline: Duration,
    interval: Duration,
) -> Result<()> {
    if !r.dry_run {
        let end = Instant::now() + deadline;
        while !pane_ready(r, t, pane) {
            if Instant::now() >= end {
                eprintln!(
                    "warning: pane shell not ready after {}s — typing anyway",
                    deadline.as_secs()
                );
                break;
            }
            std::thread::sleep(interval);
        }
    }
    t.run(
        r,
        "type agent command",
        &["send-keys", "-t", pane, "-l", text],
    )?;
    Ok(())
}

fn pane_ready(r: &Runner, t: &Tmux, pane: &str) -> bool {
    let cmd = t
        .query(
            r,
            "pane command",
            &[
                "display-message",
                "-p",
                "-t",
                pane,
                "#{pane_current_command}",
            ],
        )
        .unwrap_or_default();
    if !READY_SHELLS.contains(&cmd.trim()) {
        return false;
    }
    let content = t
        .query(r, "pane content", &["capture-pane", "-p", "-t", pane])
        .unwrap_or_default();
    content.lines().any(|l| !l.trim().is_empty())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;
    use std::rc::Rc;

    #[test]
    fn sanitize_replaces_tmux_hostile_characters() {
        assert_eq!(sanitize_session_name("rel/v1.2"), "rel-v1-2");
        assert_eq!(sanitize_session_name("plain"), "plain");
        assert_eq!(sanitize_session_name("a:b"), "a-b");
    }

    #[test]
    fn type_unentered_waits_for_prompt_then_sends_literal_keys_without_enter() {
        // Scripted pane state: shell running, but prompt not drawn until the
        // second capture-pane.
        let captures = Rc::new(RefCell::new(0));
        let captures_in = captures.clone();
        let r = Runner::with_exec(move |_, args| {
            if args.contains(&"display-message") {
                Ok("sh\n".into())
            } else if args.contains(&"capture-pane") {
                *captures_in.borrow_mut() += 1;
                if *captures_in.borrow() == 1 {
                    Ok("".into()) // no prompt yet
                } else {
                    Ok("$ \n".into())
                }
            } else {
                Ok("".into())
            }
        });
        let t = Tmux { socket: None };

        type_unentered(
            &r,
            &t,
            "%7",
            "claude",
            Duration::from_secs(2),
            Duration::from_millis(1),
        )
        .unwrap();

        assert_eq!(*captures.borrow(), 2, "must poll until the prompt appears");
        let planned = r.planned();
        let send = planned.last().unwrap();
        assert!(
            send.contains("send-keys") && send.contains("-l") && send.contains("claude"),
            "literal send-keys must be last: {planned:?}"
        );
        assert!(
            !planned.iter().any(|c| c.contains("Enter")),
            "Enter must never be sent: {planned:?}"
        );
    }

    #[test]
    fn type_unentered_times_out_and_types_anyway() {
        let r = Runner::with_exec(|_, args| {
            if args.contains(&"display-message") {
                Ok("nix\n".into()) // never a shell — readiness never true
            } else {
                Ok("".into())
            }
        });
        let t = Tmux { socket: None };

        type_unentered(
            &r,
            &t,
            "%7",
            "claude",
            Duration::from_millis(5),
            Duration::from_millis(1),
        )
        .unwrap();

        assert!(
            r.planned().iter().any(|c| c.contains("send-keys")),
            "must still type after timeout: {:?}",
            r.planned()
        );
    }
}
