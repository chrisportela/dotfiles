//! `wt open` — reopen the tmux workspace for worktrees that already exist on
//! disk (the post-reboot case: worktrees survive, tmux windows don't). The
//! claude pane gets `claude --continue` typed un-entered, so Enter resumes
//! the latest conversation in that directory.

use std::path::PathBuf;

use anyhow::{Result, bail};

use crate::cmd::Runner;
use crate::git;
use crate::resolve::TargetKind;
use crate::tmux;

/// Typed into the claude pane on open — resumes the directory's latest
/// conversation. Never entered automatically; the user can edit it first.
pub const AGENT_RESUME_CMD: &str = "claude --continue";

pub struct OpenOpts {
    /// `None` means restore-all: every registered worktree without a live
    /// tmux window.
    pub target: Option<String>,
    /// Which interpretations of `target` to try.
    pub kind: TargetKind,
    pub session: bool,
}

/// A worktree `open` will act on.
#[derive(Debug, PartialEq, Eq)]
pub struct Target {
    pub branch: String,
    pub path: PathBuf,
}

/// Which worktrees to open. With a target (branch name, .worktrees/ folder
/// name, or path — see resolve::find): exactly that worktree, or a clean
/// error pointing at `wt add`. Without: every non-main worktree that is on a
/// branch (detached worktrees have no branch to name a window after — wt
/// never creates those, so they are silently skipped).
pub fn resolve(
    worktrees: &[git::Worktree],
    root: &std::path::Path,
    target: Option<(&str, TargetKind)>,
) -> Result<Vec<Target>> {
    match target {
        Some((name, kind)) => {
            let found = crate::resolve::find(worktrees, root, name, kind).map_err(|e| {
                match e.downcast_ref::<crate::resolve::FindError>() {
                    Some(crate::resolve::FindError::NoMatch(_)) => {
                        anyhow::anyhow!("{e} — create one with `wt add {name}`")
                    }
                    _ => e,
                }
            })?;
            let Some(branch) = found.branch else {
                bail!(
                    "worktree at {} is on a detached HEAD — tmux windows are \
                     named after branches, so `wt open` cannot target it",
                    found.path.display()
                );
            };
            Ok(vec![Target {
                branch,
                path: found.path,
            }])
        }
        None => Ok(worktrees
            .iter()
            .filter(|w| !w.is_main)
            .filter_map(|w| {
                Some(Target {
                    branch: w.branch.clone()?,
                    path: w.path.clone(),
                })
            })
            .collect()),
    }
}

pub fn run(r: &Runner, opts: &OpenOpts) -> Result<()> {
    let root = git::repo_root(r)?;
    let worktrees = git::list_worktrees(r, &root)?;
    let targets = resolve(
        &worktrees,
        &root,
        opts.target.as_deref().map(|t| (t, opts.kind)),
    )?;
    if targets.is_empty() {
        println!("No worktrees to open (create one with `wt add <branch>`).");
        return Ok(());
    }

    let restore_all = opts.target.is_none();
    let t = tmux::Tmux::from_env();
    for target in &targets {
        if !target.path.is_dir() {
            eprintln!(
                "warning: worktree for '{}' is registered but missing on disk at {} — \
                 skipping (git worktree prune?)",
                target.branch,
                target.path.display()
            );
            continue;
        }
        // Single mode wants the existing window selected (open_workspace does
        // that); restore-all must not hop through every open workspace.
        if restore_all && already_open(r, &t, &target.branch, opts.session) {
            println!("'{}' already open — skipping", target.branch);
            continue;
        }
        tmux::open_workspace(
            r,
            &target.branch,
            &target.path,
            opts.session,
            AGENT_RESUME_CMD,
        )?;
    }
    Ok(())
}

fn already_open(r: &Runner, t: &tmux::Tmux, branch: &str, want_session: bool) -> bool {
    if want_session {
        return t.has_session(r, &tmux::sanitize_session_name(branch));
    }
    t.inside_tmux()
        && t.current_session(r)
            .is_some_and(|s| t.window_named(r, &s, branch).is_some())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::git::Worktree;
    use std::path::Path;

    fn wt(path: &str, branch: Option<&str>, is_main: bool) -> Worktree {
        Worktree {
            path: PathBuf::from(path),
            head: "0".repeat(40),
            branch: branch.map(str::to_string),
            is_main,
        }
    }

    fn root() -> PathBuf {
        PathBuf::from("/r")
    }

    fn one(wts: &[Worktree], target: &str) -> Result<Vec<Target>> {
        resolve(wts, &root(), Some((target, TargetKind::Any)))
    }

    #[test]
    fn resolve_single_finds_the_matching_worktree() {
        let wts = vec![
            wt("/r", Some("main"), true),
            wt("/r/.worktrees/feature/x", Some("feature/x"), false),
        ];
        let targets = one(&wts, "feature/x").unwrap();
        assert_eq!(
            targets,
            vec![Target {
                branch: "feature/x".into(),
                path: PathBuf::from("/r/.worktrees/feature/x"),
            }]
        );
    }

    #[test]
    fn resolve_single_finds_by_folder_name_when_branch_differs() {
        let wts = vec![
            wt("/r", Some("main"), true),
            wt("/r/.worktrees/dir-x", Some("branch-x"), false),
        ];
        let targets = one(&wts, "dir-x").unwrap();
        assert_eq!(
            targets,
            vec![Target {
                branch: "branch-x".into(),
                path: PathBuf::from("/r/.worktrees/dir-x"),
            }]
        );
    }

    #[test]
    fn resolve_single_finds_by_path_outside_the_repo() {
        let wts = vec![
            wt("/r", Some("main"), true),
            wt("/home/u/.claude/worktrees/ext", Some("ext-branch"), false),
        ];
        let targets = one(&wts, "/home/u/.claude/worktrees/ext").unwrap();
        assert_eq!(targets[0].branch, "ext-branch");
    }

    #[test]
    fn resolve_single_detached_match_is_clean_error() {
        // Windows are named after branches — a detached worktree has none.
        let wts = vec![
            wt("/r", Some("main"), true),
            wt("/r/.worktrees/loose", None, false),
        ];
        let err = one(&wts, "loose").unwrap_err().to_string();
        assert!(err.contains("detached"), "got: {err}");
    }

    #[test]
    fn resolve_single_unknown_target_errors_with_add_hint() {
        let wts = vec![wt("/r", Some("main"), true)];
        let err = one(&wts, "nope").unwrap_err().to_string();
        assert!(err.contains("no worktree"), "got: {err}");
        assert!(err.contains("wt add"), "should hint at wt add: {err}");
    }

    #[test]
    fn resolve_single_ambiguous_target_keeps_flag_guidance_without_add_hint() {
        let wts = vec![
            wt("/r", Some("main"), true),
            wt("/r/.worktrees/other", Some("confusing"), false),
            wt("/r/.worktrees/confusing", Some("something-else"), false),
        ];
        let err = one(&wts, "confusing").unwrap_err().to_string();
        assert!(err.contains("ambiguous"), "got: {err}");
        assert!(
            !err.contains("wt add"),
            "ambiguity must not suggest creating a worktree: {err}"
        );
    }

    #[test]
    fn resolve_single_never_matches_the_main_checkout() {
        let wts = vec![wt("/r", Some("main"), true)];
        assert!(one(&wts, "main").is_err());
    }

    #[test]
    fn resolve_all_excludes_main_and_detached() {
        let wts = vec![
            wt("/r", Some("main"), true),
            wt("/r/.worktrees/a", Some("a"), false),
            wt("/r/.worktrees/experiment", None, false), // detached
            wt("/r/.worktrees/b/c", Some("b/c"), false),
        ];
        let targets = resolve(&wts, &root(), None).unwrap();
        let branches: Vec<&str> = targets.iter().map(|t| t.branch.as_str()).collect();
        assert_eq!(branches, vec!["a", "b/c"]);
        assert_eq!(targets[0].path, Path::new("/r/.worktrees/a"));
    }

    #[test]
    fn resolve_all_with_only_main_is_empty_not_an_error() {
        let wts = vec![wt("/r", Some("main"), true)];
        assert_eq!(resolve(&wts, &root(), None).unwrap(), vec![]);
    }
}
