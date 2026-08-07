//! `wt rm` — interactively remove a worktree, then offer to merge and delete
//! its branch, clean up emptied container dirs, and kill the tmux window.
//!
//! The tmux window kill comes LAST: if the user runs `wt rm` from inside
//! that very window, everything else has completed before the pane dies.

use std::path::Path;

use anyhow::{Result, bail};

use crate::cmd::Runner;
use crate::git;
use crate::prompt::confirm;
use crate::tmux;

pub struct RmOpts {
    pub name: String,
    pub no_tmux: bool,
}

pub fn run(r: &Runner, opts: &RmOpts) -> Result<()> {
    let name = opts.name.as_str();
    let root = git::repo_root(r)?;
    let worktrees_root = root.join(git::WORKTREE_DIR);
    let wt_path = worktrees_root.join(name);

    // Resolve against REGISTERED worktrees, not the filesystem — a stale
    // container dir like `.worktrees/cportela/` is not removable.
    let worktrees = git::list_worktrees(r, &root)?;
    let Some(target) = worktrees.iter().find(|w| !w.is_main && w.path == wt_path) else {
        bail!("no worktree '{name}' (see wt ls)");
    };
    let branch = target.branch.clone();

    let inside_victim = std::env::current_dir()
        .ok()
        .and_then(|d| std::fs::canonicalize(d).ok())
        .is_some_and(|d| d.starts_with(&wt_path));

    // Dirty check + force prompt.
    let dirty = git::status_porcelain(r, &wt_path)?;
    let mut force = false;
    if !dirty.trim().is_empty() {
        println!("Worktree has uncommitted/untracked files:");
        print!("{dirty}");
        println!();
        if confirm("Force remove worktree?", false)? {
            force = true;
        } else {
            println!("Aborted.");
            return Ok(());
        }
    }

    let mut remove_args = vec!["worktree", "remove"];
    if force {
        remove_args.push("--force");
    }
    let wt_path_str = wt_path.display().to_string();
    remove_args.push(&wt_path_str);
    r.run("remove worktree", "git", &remove_args, Some(&root))?;
    println!("Removed worktree at {}/{name}", git::WORKTREE_DIR);

    if !r.dry_run {
        clean_empty_parents(&worktrees_root, &wt_path);
    }

    branch_afterlife(r, &root, branch.as_deref())?;

    // Kill the matching tmux window (named after the worktree) last.
    if !opts.no_tmux {
        let t = tmux::Tmux::from_env();
        if t.inside_tmux()
            && let Some(session) = t.current_session(r)
            && let Some(window_id) = t.window_named(r, &session, name)
            && confirm(&format!("Kill tmux window '{name}'?"), true)?
        {
            t.kill_window(r, &window_id)?;
        }
    }

    if inside_victim {
        println!(
            "note: your shell is inside the removed worktree — cd {}",
            root.display()
        );
    }
    Ok(())
}

fn branch_afterlife(r: &Runner, root: &Path, branch: Option<&str>) -> Result<()> {
    let Some(branch) = branch else {
        println!("Worktree was on a detached HEAD — no branch to merge or delete.");
        return Ok(());
    };
    if !git::local_branch_exists(r, root, branch) {
        println!("Branch '{branch}' does not exist (may have been removed already).");
        return Ok(());
    }

    // Offer merge into the current branch of the main checkout.
    let mut merged = false;
    match git::current_branch(r, root) {
        Some(current) => {
            if confirm(&format!("Merge branch '{branch}' into {current}?"), false)? {
                if r.run("merge branch", "git", &["merge", branch], Some(root))
                    .is_ok()
                {
                    merged = true;
                    println!("Merged '{branch}' into {current}");
                } else {
                    eprintln!("Merge failed — resolve conflicts manually.");
                    return Ok(());
                }
            }
        }
        None => println!("note: main checkout is on a detached HEAD — skipping merge offer."),
    }

    if !confirm(&format!("Delete branch '{branch}'?"), true)? {
        println!("Keeping branch '{branch}'.");
        return Ok(());
    }

    if r.run(
        "delete branch",
        "git",
        &["branch", "-d", branch],
        Some(root),
    )
    .is_ok()
    {
        println!("Deleted branch '{branch}'.");
        return Ok(());
    }
    if merged {
        eprintln!("warning: could not delete branch '{branch}' even after merge.");
        return Ok(());
    }

    let force_delete = if git::upstream_gone(r, root, branch) {
        println!("Branch '{branch}' is not fully merged locally, but its upstream");
        println!("tracking branch is gone. This usually means it was squash- or");
        println!("rebase-merged on the remote and then deleted (common on GitHub");
        println!("PR merge). Recommending force delete.");
        confirm("Force delete branch?", true)?
    } else {
        println!("Branch '{branch}' is not fully merged.");
        confirm("Force delete branch?", false)?
    };
    if force_delete {
        r.run(
            "force delete branch",
            "git",
            &["branch", "-D", branch],
            Some(root),
        )?;
        println!("Force deleted branch '{branch}'.");
    } else {
        println!("Keeping branch '{branch}'.");
    }
    Ok(())
}

/// Remove now-empty parent directories of a removed worktree, staying
/// strictly inside .worktrees/.
fn clean_empty_parents(worktrees_root: &Path, removed: &Path) {
    let mut dir: Option<&Path> = removed.parent();
    while let Some(d) = dir {
        if d == worktrees_root || !d.starts_with(worktrees_root) {
            break;
        }
        let empty = std::fs::read_dir(d)
            .map(|mut it| it.next().is_none())
            .unwrap_or(false);
        if !empty || std::fs::remove_dir(d).is_err() {
            break;
        }
        dir = d.parent();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn touch_dir(p: &Path) {
        std::fs::create_dir_all(p).unwrap();
    }

    #[test]
    fn clean_empty_parents_removes_chain_but_stops_at_worktrees_root() {
        let base = std::env::temp_dir().join(format!("wt-rm-clean-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&base);
        let wts = base.join(".worktrees");
        touch_dir(&wts.join("a/b")); // removed worktree was .worktrees/a/b/c

        clean_empty_parents(&wts, &wts.join("a/b/c"));

        assert!(!wts.join("a").exists(), "empty chain removed");
        assert!(wts.exists(), ".worktrees survives");
        std::fs::remove_dir_all(&base).unwrap();
    }

    #[test]
    fn clean_empty_parents_stops_at_non_empty_dir() {
        let base = std::env::temp_dir().join(format!("wt-rm-clean2-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&base);
        let wts = base.join(".worktrees");
        touch_dir(&wts.join("a/b"));
        std::fs::write(wts.join("a/other.txt"), "x").unwrap();

        clean_empty_parents(&wts, &wts.join("a/b/c"));

        assert!(!wts.join("a/b").exists());
        assert!(wts.join("a").exists(), "non-empty dir kept");
        std::fs::remove_dir_all(&base).unwrap();
    }

    #[test]
    fn clean_empty_parents_never_escapes_worktrees_root() {
        let base = std::env::temp_dir().join(format!("wt-rm-clean3-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&base);
        let wts = base.join(".worktrees");
        touch_dir(&wts);

        // Removed path directly under .worktrees — nothing to clean, and the
        // walk must not touch .worktrees or anything above it.
        clean_empty_parents(&wts, &wts.join("solo"));

        assert!(wts.exists());
        assert!(base.exists());
        std::fs::remove_dir_all(&base).unwrap();
    }
}
