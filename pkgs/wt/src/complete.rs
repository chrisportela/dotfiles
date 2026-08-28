//! `wt __complete <targets|worktrees|branches>` — dynamic completion
//! candidates for the shell completion scripts. Prints one candidate per
//! line. Never fails: completion must stay silent when something is off (not
//! a repo, no .worktrees/), so every error collapses to empty output.
//!
//! `targets` (open/rm) is folder names ∪ worktree branch names — everything
//! the unified resolver accepts short of a filesystem path. `worktrees` is
//! kept so stale installed completion scripts don't go silent.

use anyhow::Result;

use crate::cmd::Runner;
use crate::git;

pub fn run(r: &Runner, what: &str) -> Result<()> {
    for candidate in candidates(r, what) {
        println!("{candidate}");
    }
    Ok(())
}

fn candidates(r: &Runner, what: &str) -> Vec<String> {
    let Ok(root) = git::repo_root(r) else {
        return Vec::new();
    };
    match what {
        "targets" => {
            let base = root.join(git::WORKTREE_DIR);
            let mut seen = std::collections::HashSet::new();
            git::list_worktrees(r, &root)
                .unwrap_or_default()
                .iter()
                .filter(|wt| !wt.is_main)
                .flat_map(|wt| {
                    let folder = wt
                        .path
                        .strip_prefix(&base)
                        .ok()
                        .map(|rel| rel.display().to_string());
                    folder.into_iter().chain(wt.branch.clone())
                })
                .filter(|c| !c.is_empty())
                .filter(|c| seen.insert(c.clone()))
                .collect()
        }
        "worktrees" => {
            let base = root.join(git::WORKTREE_DIR);
            git::list_worktrees(r, &root)
                .unwrap_or_default()
                .iter()
                .filter_map(|wt| Some(wt.path.strip_prefix(&base).ok()?.display().to_string()))
                .filter(|rel| !rel.is_empty())
                .collect()
        }
        "branches" => {
            let checked_out: Vec<String> = git::list_worktrees(r, &root)
                .unwrap_or_default()
                .into_iter()
                .filter_map(|wt| wt.branch)
                .collect();
            let local = branch_names(
                r,
                &["for-each-ref", "--format=%(refname:short)", "refs/heads"],
                &root,
            );
            let remote = branch_names(
                r,
                &[
                    "for-each-ref",
                    "--format=%(refname:lstrip=3)",
                    "refs/remotes",
                ],
                &root,
            );
            let mut seen = std::collections::HashSet::new();
            local
                .into_iter()
                .chain(remote)
                .filter(|b| !b.is_empty() && b != "HEAD" && !checked_out.contains(b))
                .filter(|b| seen.insert(b.clone()))
                .collect()
        }
        _ => Vec::new(),
    }
}

fn branch_names(r: &Runner, args: &[&str], root: &std::path::Path) -> Vec<String> {
    r.query("list refs", "git", args, Some(root))
        .map(|out| out.lines().map(str::to_string).collect())
        .unwrap_or_default()
}
