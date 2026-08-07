//! `wt init` — create .worktrees/ and hide it from git via .git/info/exclude.

use std::path::Path;

use anyhow::Result;

use crate::cmd::Runner;
use crate::git;

pub fn run(r: &Runner) -> Result<()> {
    let root = git::repo_root(r)?;
    run_at(r, &root)
}

/// Idempotent; callable from `add`'s auto-init with a known root.
pub fn run_at(r: &Runner, root: &Path) -> Result<()> {
    let wt_dir = root.join(git::WORKTREE_DIR);
    if wt_dir.is_dir() {
        println!(".worktrees/ already exists");
    } else {
        r.fs(
            "create worktrees dir",
            &format!("mkdir -p {}", wt_dir.display()),
            || Ok(std::fs::create_dir_all(&wt_dir)?),
        )?;
        println!("Created .worktrees/");
    }

    // --git-common-dir so init works from inside a worktree too.
    let info_dir = git::common_git_dir(r, root)?.join("info");
    let exclude = info_dir.join("exclude");
    let existing = std::fs::read_to_string(&exclude).unwrap_or_default();
    if existing
        .lines()
        .any(|l| l == ".worktrees/" || l == ".worktrees")
    {
        println!(".worktrees/ already in .git/info/exclude");
    } else {
        r.fs(
            "update git exclude",
            &format!("append .worktrees/ to {}", exclude.display()),
            || {
                std::fs::create_dir_all(&info_dir)?;
                let mut content = existing.clone();
                if !content.is_empty() && !content.ends_with('\n') {
                    content.push('\n');
                }
                content.push_str(".worktrees/\n");
                std::fs::write(&exclude, content)?;
                Ok(())
            },
        )?;
        println!("Added .worktrees/ to .git/info/exclude");
    }
    Ok(())
}
