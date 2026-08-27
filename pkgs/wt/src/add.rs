//! `wt add` — create a worktree at .worktrees/<branch>, set it up, open tmux.

use anyhow::{Result, bail};

use crate::cmd::Runner;
use crate::git;
use crate::init;
use crate::setup;
use crate::tmux;

pub struct AddOpts {
    pub branch: String,
    pub no_direnv: bool,
    pub no_env: bool,
    pub no_tmux: bool,
    pub session: bool,
}

/// How `add` will obtain the branch — mirrors `git checkout` DWIM.
#[derive(Debug, PartialEq, Eq)]
pub enum AddPlan {
    /// Branch exists locally: check it out.
    ExistingLocal,
    /// Exactly one remote has it: create a local tracking branch of this short ref.
    TrackRemote(String),
    /// Nobody has it: new branch off HEAD.
    NewBranch,
    /// Same name on several remotes: refuse, listing candidates.
    AmbiguousRemotes(Vec<String>),
}

pub fn resolve(local_exists: bool, mut remote_matches: Vec<String>) -> AddPlan {
    if local_exists {
        return AddPlan::ExistingLocal;
    }
    match remote_matches.len() {
        0 => AddPlan::NewBranch,
        1 => AddPlan::TrackRemote(remote_matches.remove(0)),
        _ => AddPlan::AmbiguousRemotes(remote_matches),
    }
}

pub fn run(r: &Runner, opts: &AddOpts) -> Result<()> {
    let branch = opts.branch.as_str();
    let root = git::repo_root(r)?;
    let wt_dir = root.join(git::WORKTREE_DIR);
    if !wt_dir.is_dir() {
        init::run_at(r, &root)?;
    }
    let wt_path = wt_dir.join(branch);
    let wt_path_str = wt_path.display().to_string();

    let worktrees = git::list_worktrees(r, &root)?;
    if let Some(existing) = worktrees
        .iter()
        .find(|w| w.branch.as_deref() == Some(branch))
    {
        bail!(
            "branch '{branch}' is already checked out at {}",
            existing.path.display()
        );
    }
    if wt_path.exists() && !worktrees.iter().any(|w| w.path == wt_path) {
        bail!(
            "{}/{branch} exists but is not a registered worktree — \
             remove the directory or run `git worktree prune`",
            git::WORKTREE_DIR
        );
    }
    if wt_path.exists() {
        bail!("worktree already exists at {}/{branch}", git::WORKTREE_DIR);
    }

    let local = git::local_branch_exists(r, &root, branch);
    let remotes = git::remote_matches(r, &root, branch)?;
    match resolve(local, remotes) {
        AddPlan::ExistingLocal => {
            println!("Checking out existing branch '{branch}'");
            r.run(
                "add worktree",
                "git",
                &["worktree", "add", &wt_path_str, branch],
                Some(&root),
            )?;
        }
        AddPlan::TrackRemote(short_ref) => {
            println!("Tracking remote branch '{short_ref}' as '{branch}'");
            r.run(
                "add worktree",
                "git",
                &[
                    "worktree",
                    "add",
                    "--track",
                    "-b",
                    branch,
                    &wt_path_str,
                    &short_ref,
                ],
                Some(&root),
            )?;
        }
        AddPlan::NewBranch => {
            println!("Creating new branch '{branch}'");
            r.run(
                "add worktree",
                "git",
                &["worktree", "add", "-b", branch, &wt_path_str],
                Some(&root),
            )?;
        }
        AddPlan::AmbiguousRemotes(candidates) => {
            bail!(
                "branch '{branch}' exists on multiple remotes:\n  {}\n\
                 Resolve manually: git worktree add {wt_path_str} -b {branch} --track <remote>/{branch}",
                candidates.join("\n  ")
            );
        }
    }

    setup::run(
        r,
        &root,
        &wt_path,
        &setup::SetupOpts {
            no_direnv: opts.no_direnv,
            no_env: opts.no_env,
        },
    )?;

    if !opts.no_tmux {
        tmux::open_workspace(r, branch, &wt_path, opts.session, "claude")?;
    }

    println!();
    println!("Worktree ready at: {}/{branch}", git::WORKTREE_DIR);
    println!("  cd {wt_path_str}");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolve_prefers_existing_local_branch() {
        assert_eq!(
            resolve(true, vec!["origin/foo".into()]),
            AddPlan::ExistingLocal
        );
    }

    #[test]
    fn resolve_tracks_unique_remote_match() {
        assert_eq!(
            resolve(false, vec!["origin/foo".into()]),
            AddPlan::TrackRemote("origin/foo".into())
        );
    }

    #[test]
    fn resolve_creates_new_branch_when_nowhere() {
        assert_eq!(resolve(false, vec![]), AddPlan::NewBranch);
    }

    #[test]
    fn resolve_refuses_multi_remote_collision() {
        assert_eq!(
            resolve(false, vec!["origin/foo".into(), "fork/foo".into()]),
            AddPlan::AmbiguousRemotes(vec!["origin/foo".into(), "fork/foo".into()])
        );
    }
}
