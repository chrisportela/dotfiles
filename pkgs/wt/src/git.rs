//! Git queries. All state is derived from git itself (`worktree list
//! --porcelain`, `for-each-ref`, `ls-files`) — wt keeps no state file.

use std::path::{Path, PathBuf};

use anyhow::{Result, anyhow};

use crate::cmd::Runner;

pub const WORKTREE_DIR: &str = ".worktrees";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Worktree {
    pub path: PathBuf,
    pub head: String,
    /// Branch name without the `refs/heads/` prefix; `None` when detached or bare.
    pub branch: Option<String>,
    /// The main checkout — always the first entry in porcelain output.
    pub is_main: bool,
}

/// Parse `git worktree list --porcelain` output.
pub fn parse_porcelain(text: &str) -> Vec<Worktree> {
    let mut result: Vec<Worktree> = Vec::new();
    for line in text.lines() {
        if let Some(path) = line.strip_prefix("worktree ") {
            result.push(Worktree {
                path: PathBuf::from(path),
                head: String::new(),
                branch: None,
                is_main: result.is_empty(),
            });
            continue;
        }
        let Some(current) = result.last_mut() else {
            continue;
        };
        if let Some(head) = line.strip_prefix("HEAD ") {
            current.head = head.to_string();
        } else if let Some(refname) = line.strip_prefix("branch ") {
            current.branch = Some(
                refname
                    .strip_prefix("refs/heads/")
                    .unwrap_or(refname)
                    .to_string(),
            );
        }
        // "detached" and "bare" lines leave branch as None.
    }
    result
}

pub fn repo_root(r: &Runner) -> Result<PathBuf> {
    let out = r
        .query(
            "locate repo",
            "git",
            &["rev-parse", "--show-toplevel"],
            None,
        )
        .map_err(|_| anyhow!("not in a git repository"))?;
    Ok(PathBuf::from(out.trim_end()))
}

/// The shared .git directory — resolves correctly from inside a worktree,
/// where `.git` is a file and per-worktree gitdirs live elsewhere.
pub fn common_git_dir(r: &Runner, root: &Path) -> Result<PathBuf> {
    let out = r.query(
        "locate common git dir",
        "git",
        &["rev-parse", "--git-common-dir"],
        Some(root),
    )?;
    let dir = PathBuf::from(out.trim_end());
    Ok(if dir.is_absolute() {
        dir
    } else {
        root.join(dir)
    })
}

pub fn list_worktrees(r: &Runner, root: &Path) -> Result<Vec<Worktree>> {
    let out = r.query(
        "list worktrees",
        "git",
        &["worktree", "list", "--porcelain"],
        Some(root),
    )?;
    Ok(parse_porcelain(&out))
}

pub fn local_branch_exists(r: &Runner, root: &Path, branch: &str) -> bool {
    r.query(
        "check local branch",
        "git",
        &[
            "show-ref",
            "--verify",
            "--quiet",
            &format!("refs/heads/{branch}"),
        ],
        Some(root),
    )
    .is_ok()
}

/// Remote-tracking branches named `branch`, as short refs (e.g. `origin/foo`).
pub fn remote_matches(r: &Runner, root: &Path, branch: &str) -> Result<Vec<String>> {
    let out = r.query(
        "list remote branches",
        "git",
        &[
            "for-each-ref",
            "--format=%(refname:lstrip=2)",
            &format!("refs/remotes/*/{branch}"),
        ],
        Some(root),
    )?;
    Ok(out.lines().map(str::to_string).collect())
}

/// True iff the branch has an upstream tracking ref that is now gone —
/// the typical state after a squash-/rebase-merge deleted the PR branch.
pub fn upstream_gone(r: &Runner, root: &Path, branch: &str) -> bool {
    r.query(
        "check upstream",
        "git",
        &[
            "for-each-ref",
            "--format=%(upstream:track)",
            &format!("refs/heads/{branch}"),
        ],
        Some(root),
    )
    .map(|out| out.contains("[gone]"))
    .unwrap_or(false)
}

/// Current branch name, `None` on detached HEAD.
pub fn current_branch(r: &Runner, root: &Path) -> Option<String> {
    let out = r
        .query(
            "current branch",
            "git",
            &["branch", "--show-current"],
            Some(root),
        )
        .ok()?;
    let name = out.trim_end();
    if name.is_empty() {
        None
    } else {
        Some(name.to_string())
    }
}

pub fn status_porcelain(r: &Runner, worktree: &Path) -> Result<String> {
    r.query(
        "check worktree status",
        "git",
        &["status", "--porcelain"],
        Some(worktree),
    )
}

/// Present-but-not-tracked files in the main checkout matching `patterns`:
/// plain untracked plus ignored/excluded (covers .git/info/exclude and
/// .gitignore). Paths under .worktrees/ are dropped. Order preserved, deduped.
pub fn untracked_matching(r: &Runner, root: &Path, patterns: &[&str]) -> Result<Vec<PathBuf>> {
    let mut args_base = vec!["ls-files", "--others", "--exclude-standard", "-z", "--"];
    args_base.extend_from_slice(patterns);
    let mut args_ignored = vec![
        "ls-files",
        "--others",
        "--ignored",
        "--exclude-standard",
        "-z",
        "--",
    ];
    args_ignored.extend_from_slice(patterns);

    let plain = r.query("list untracked files", "git", &args_base, Some(root))?;
    let ignored = r.query("list excluded files", "git", &args_ignored, Some(root))?;

    let mut seen = std::collections::HashSet::new();
    let mut result = Vec::new();
    for rel in plain.split('\0').chain(ignored.split('\0')) {
        if rel.is_empty() || rel.starts_with(&format!("{WORKTREE_DIR}/")) {
            continue;
        }
        if seen.insert(rel.to_string()) {
            result.push(PathBuf::from(rel));
        }
    }
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_porcelain_main_nested_and_detached() {
        let text = "\
worktree /home/u/repo
HEAD 1111111111111111111111111111111111111111
branch refs/heads/main

worktree /home/u/repo/.worktrees/cportela/feature-x
HEAD 2222222222222222222222222222222222222222
branch refs/heads/cportela/feature-x

worktree /home/u/repo/.worktrees/experiment
HEAD 3333333333333333333333333333333333333333
detached
";
        let wts = parse_porcelain(text);
        assert_eq!(wts.len(), 3);

        assert!(wts[0].is_main);
        assert_eq!(wts[0].path, PathBuf::from("/home/u/repo"));
        assert_eq!(wts[0].branch.as_deref(), Some("main"));

        assert!(!wts[1].is_main);
        assert_eq!(
            wts[1].path,
            PathBuf::from("/home/u/repo/.worktrees/cportela/feature-x")
        );
        assert_eq!(wts[1].branch.as_deref(), Some("cportela/feature-x"));
        assert_eq!(wts[1].head, "2222222222222222222222222222222222222222");

        assert!(!wts[2].is_main);
        assert_eq!(wts[2].branch, None, "detached worktree has no branch");
    }

    #[test]
    fn parse_porcelain_bare_repo_entry() {
        let text = "\
worktree /home/u/repo.git
bare

worktree /home/u/wt
HEAD 4444444444444444444444444444444444444444
branch refs/heads/dev
";
        let wts = parse_porcelain(text);
        assert_eq!(wts.len(), 2);
        assert!(wts[0].is_main);
        assert_eq!(wts[0].branch, None, "bare entry has no branch");
        assert_eq!(wts[1].branch.as_deref(), Some("dev"));
    }

    #[test]
    fn parse_porcelain_empty_input() {
        assert!(parse_porcelain("").is_empty());
    }

    #[test]
    fn upstream_gone_only_when_track_says_gone() {
        let gone = Runner::with_exec(|_, _| Ok("[gone]\n".into()));
        assert!(upstream_gone(&gone, Path::new("/r"), "b"));

        let ahead = Runner::with_exec(|_, _| Ok("[ahead 2]\n".into()));
        assert!(!upstream_gone(&ahead, Path::new("/r"), "b"));

        let none = Runner::with_exec(|_, _| Ok("\n".into()));
        assert!(!upstream_gone(&none, Path::new("/r"), "b"));
    }

    #[test]
    fn untracked_matching_unions_dedupes_and_skips_worktrees_dir() {
        let r = Runner::with_exec(|_, args| {
            if args.contains(&"--ignored") {
                Ok(".envrc\0sub/.envrc\0.worktrees/x/.envrc\0".into())
            } else {
                Ok(".envrc\0fresh/.envrc\0".into())
            }
        });
        let got = untracked_matching(&r, Path::new("/r"), &[".envrc", "*/.envrc"]).unwrap();
        assert_eq!(
            got,
            vec![
                PathBuf::from(".envrc"),
                PathBuf::from("fresh/.envrc"),
                PathBuf::from("sub/.envrc"),
            ]
        );
    }

    #[test]
    fn current_branch_none_when_detached() {
        let detached = Runner::with_exec(|_, _| Ok("\n".into()));
        assert_eq!(current_branch(&detached, Path::new("/r")), None);

        let on_branch = Runner::with_exec(|_, _| Ok("main\n".into()));
        assert_eq!(
            current_branch(&on_branch, Path::new("/r")).as_deref(),
            Some("main")
        );
    }
}
