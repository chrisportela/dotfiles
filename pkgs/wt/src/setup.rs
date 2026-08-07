//! Worktree setup after `git worktree add`, before any tmux pane exists.
//!
//! Order is load-bearing:
//! 1. copy untracked/excluded .envrc files (fresh worktrees lack them),
//! 2. copy .env files (an .envrc may dotenv-read them),
//! 3. `direnv allow` every .envrc in the worktree,
//! 4. `direnv exec <wt> true` to prime the devshell — so a slow first nix
//!    eval happens here, narrated, instead of hanging a fresh tmux pane.

use std::path::{Path, PathBuf};

use anyhow::Result;

use crate::cmd::Runner;
use crate::git;

pub struct SetupOpts {
    pub no_direnv: bool,
    pub no_env: bool,
}

pub fn run(r: &Runner, root: &Path, wt_path: &Path, opts: &SetupOpts) -> Result<()> {
    copy_untracked(r, root, wt_path, &[".envrc", "*/.envrc"])?;
    if !opts.no_env {
        copy_untracked(r, root, wt_path, &[".env", "*/.env"])?;
    }

    if opts.no_direnv || !on_path("direnv") {
        return Ok(());
    }
    let envrcs = find_envrcs(wt_path);
    if envrcs.is_empty() {
        return Ok(());
    }
    println!();
    println!("Approving {} .envrc file(s) with direnv:", envrcs.len());
    for rel in &envrcs {
        let abs = wt_path.join(rel);
        r.run(
            "direnv allow",
            "direnv",
            &["allow", &abs.display().to_string()],
            None,
        )?;
        println!("  allowed: {}", rel.display());
    }
    println!("Priming direnv environment (first nix eval can take a while)…");
    r.run(
        "direnv prime",
        "direnv",
        &["exec", &wt_path.display().to_string(), "true"],
        Some(wt_path),
    )?;
    Ok(())
}

/// Copy main-checkout files matching `patterns` that git does not track
/// (untracked or excluded — they won't materialize in a fresh worktree).
/// Files already present in the worktree are left alone.
fn copy_untracked(r: &Runner, root: &Path, wt_path: &Path, patterns: &[&str]) -> Result<()> {
    for rel in git::untracked_matching(r, root, patterns)? {
        let src = root.join(&rel);
        let dst = wt_path.join(&rel);
        if !src.is_file() || dst.exists() {
            continue;
        }
        r.fs(
            "copy env file",
            &format!("copy {} into worktree", rel.display()),
            || {
                if let Some(parent) = dst.parent() {
                    std::fs::create_dir_all(parent)?;
                }
                std::fs::copy(&src, &dst)?;
                Ok(())
            },
        )?;
        println!("  copied: {}", rel.display());
    }
    Ok(())
}

pub fn on_path(program: &str) -> bool {
    let Some(path) = std::env::var_os("PATH") else {
        return false;
    };
    std::env::split_paths(&path).any(|dir| dir.join(program).is_file())
}

/// All .envrc files in the worktree, as sorted relative paths. Skips .git
/// (a *file* in worktrees, but skipped by name either way), node_modules,
/// and .direnv.
fn find_envrcs(wt_path: &Path) -> Vec<PathBuf> {
    let mut found = Vec::new();
    walk(wt_path, wt_path, &mut found);
    found.sort();
    found
}

fn walk(base: &Path, dir: &Path, found: &mut Vec<PathBuf>) {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let name = entry.file_name();
        if name == ".git" || name == "node_modules" || name == ".direnv" {
            continue;
        }
        let path = entry.path();
        if path.is_dir() {
            walk(base, &path, found);
        } else if name == ".envrc"
            && let Ok(rel) = path.strip_prefix(base)
        {
            found.push(rel.to_path_buf());
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn find_envrcs_recurses_sorts_and_skips_noise_dirs() {
        let base = std::env::temp_dir().join(format!("wt-setup-walk-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&base);
        for dir in ["src", "infra", ".git/sub", "node_modules/pkg", ".direnv/wd"] {
            std::fs::create_dir_all(base.join(dir)).unwrap();
        }
        for f in [
            ".envrc",
            "src/.envrc",
            "infra/.envrc",
            ".git/sub/.envrc",
            "node_modules/pkg/.envrc",
            ".direnv/wd/.envrc",
        ] {
            std::fs::write(base.join(f), "x").unwrap();
        }

        let got = find_envrcs(&base);
        assert_eq!(
            got,
            vec![
                PathBuf::from(".envrc"),
                PathBuf::from("infra/.envrc"),
                PathBuf::from("src/.envrc"),
            ]
        );
        std::fs::remove_dir_all(&base).unwrap();
    }
}
