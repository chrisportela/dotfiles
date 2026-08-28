//! Unified target resolution. A user-supplied target may name a worktree
//! three ways — branch name, folder name relative to .worktrees/, or a
//! filesystem path (worktrees registered outside the repo included, e.g.
//! ~/.claude/worktrees/x). All interpretations are tried; matches landing on
//! the same worktree collapse, matches on distinct worktrees are refused as
//! ambiguous (disambiguate with --branch/--folder/--path).

use std::path::{Path, PathBuf};

use anyhow::Result;

use crate::git::{WORKTREE_DIR, Worktree};

/// Typed so callers can tell "nothing matched" (open appends a `wt add`
/// hint) from "several matched" (already carries its own guidance).
#[derive(Debug)]
pub enum FindError {
    NoMatch(String),
    Ambiguous(String),
}

impl std::fmt::Display for FindError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            FindError::NoMatch(msg) | FindError::Ambiguous(msg) => f.write_str(msg),
        }
    }
}

impl std::error::Error for FindError {}

/// Which interpretations of the target to try.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TargetKind {
    Any,
    Branch,
    Folder,
    Path,
}

/// Resolve `arg` to a registered non-main worktree.
pub fn find(worktrees: &[Worktree], root: &Path, arg: &str, kind: TargetKind) -> Result<Worktree> {
    use TargetKind::*;
    let candidates: Vec<&Worktree> = worktrees.iter().filter(|w| !w.is_main).collect();
    let mut matches: Vec<(&'static str, &Worktree)> = Vec::new();

    if matches!(kind, Any | Branch) {
        matches.extend(
            candidates
                .iter()
                .filter(|w| w.branch.as_deref() == Some(arg))
                .map(|w| ("branch", *w)),
        );
    }
    if matches!(kind, Any | Folder) {
        let folder_path = normalize(&root.join(WORKTREE_DIR).join(arg));
        matches.extend(
            candidates
                .iter()
                .filter(|w| normalize(&w.path) == folder_path)
                .map(|w| ("folder", *w)),
        );
    }
    if matches!(kind, Any | Path)
        && let Some(abs) = absolutize(arg)
    {
        // Lexical comparison first (worktree may be gone from disk);
        // canonical comparison second (symlinked paths, e.g. macOS /tmp).
        let canon = std::fs::canonicalize(&abs).ok();
        matches.extend(
            candidates
                .iter()
                .filter(|w| {
                    normalize(&w.path) == abs
                        || matches!(
                            (&canon, std::fs::canonicalize(&w.path)),
                            (Some(a), Ok(b)) if *a == b
                        )
                })
                .map(|w| ("path", *w)),
        );
    }

    // Interpretations landing on the same worktree collapse to one match.
    let mut distinct: Vec<(&'static str, &Worktree)> = Vec::new();
    for (how, w) in matches {
        if !distinct.iter().any(|(_, seen)| seen.path == w.path) {
            distinct.push((how, w));
        }
    }
    match distinct.as_slice() {
        [(_, only)] => Ok((*only).clone()),
        [] => {
            let tried = match kind {
                Any => "not a branch, .worktrees/ folder, or worktree path".to_string(),
                Branch => "no worktree is on that branch".to_string(),
                Folder => format!("no worktree at {WORKTREE_DIR}/{arg}"),
                Path => "no registered worktree at that path".to_string(),
            };
            Err(FindError::NoMatch(format!("no worktree '{arg}' — {tried} (see wt ls)")).into())
        }
        several => {
            let listing: Vec<String> = several
                .iter()
                .map(|(how, w)| {
                    format!(
                        "  as {how}: {} (branch {})",
                        w.path.display(),
                        w.branch.as_deref().unwrap_or("<detached>")
                    )
                })
                .collect();
            Err(FindError::Ambiguous(format!(
                "'{arg}' is ambiguous:\n{}\nUse --branch, --folder, or --path to pick one.",
                listing.join("\n")
            ))
            .into())
        }
    }
}

/// `arg` as a normalized absolute path (cwd-relative when not absolute).
fn absolutize(arg: &str) -> Option<PathBuf> {
    let home = std::env::var("HOME").ok();
    let expanded = expand_home(arg, home.as_deref());
    let abs = if expanded.is_absolute() {
        expanded
    } else {
        std::env::current_dir().ok()?.join(expanded)
    };
    Some(normalize(&abs))
}

/// Expand a leading `~/` against `home`. Pure so it stays testable.
fn expand_home(arg: &str, home: Option<&str>) -> PathBuf {
    match (arg.strip_prefix("~/"), home) {
        (Some(rest), Some(home)) => Path::new(home).join(rest),
        _ => PathBuf::from(arg),
    }
}

/// Lexically normalize a path: drop `.`, resolve `..`, strip trailing
/// slashes. No filesystem access — worktrees may be gone from disk.
fn normalize(path: &Path) -> PathBuf {
    use std::path::Component;
    let mut out = PathBuf::new();
    for c in path.components() {
        match c {
            Component::CurDir => {}
            Component::ParentDir => {
                out.pop();
            }
            other => out.push(other),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn wt(path: &str, branch: Option<&str>, is_main: bool) -> Worktree {
        Worktree {
            path: PathBuf::from(path),
            head: "0".repeat(40),
            branch: branch.map(str::to_string),
            is_main,
        }
    }

    /// main checkout + folder==branch + folder!=branch + nested + external.
    fn fixture() -> Vec<Worktree> {
        vec![
            wt("/r", Some("main"), true),
            wt("/r/.worktrees/plain", Some("plain"), false),
            wt("/r/.worktrees/dir-x", Some("branch-x"), false),
            wt("/r/.worktrees/cp/nested", Some("cp/nested"), false),
            wt("/home/u/.claude/worktrees/ext", Some("ext-branch"), false),
        ]
    }

    fn root() -> PathBuf {
        PathBuf::from("/r")
    }

    #[test]
    fn finds_by_branch_name() {
        let found = find(&fixture(), &root(), "branch-x", TargetKind::Any).unwrap();
        assert_eq!(found.path, Path::new("/r/.worktrees/dir-x"));
    }

    #[test]
    fn finds_by_folder_name_when_folder_differs_from_branch() {
        let found = find(&fixture(), &root(), "dir-x", TargetKind::Any).unwrap();
        assert_eq!(found.branch.as_deref(), Some("branch-x"));
    }

    #[test]
    fn finds_by_nested_folder_name() {
        let found = find(&fixture(), &root(), "cp/nested", TargetKind::Any).unwrap();
        assert_eq!(found.path, Path::new("/r/.worktrees/cp/nested"));
    }

    #[test]
    fn finds_by_absolute_path_outside_repo() {
        let found = find(
            &fixture(),
            &root(),
            "/home/u/.claude/worktrees/ext",
            TargetKind::Any,
        )
        .unwrap();
        assert_eq!(found.branch.as_deref(), Some("ext-branch"));
    }

    #[test]
    fn path_match_ignores_trailing_slash_and_dot_components() {
        for arg in [
            "/r/.worktrees/dir-x/",
            "/r/.worktrees/./dir-x",
            "/r/.worktrees/cp/../dir-x",
        ] {
            let found = find(&fixture(), &root(), arg, TargetKind::Any)
                .unwrap_or_else(|e| panic!("{arg}: {e}"));
            assert_eq!(found.path, Path::new("/r/.worktrees/dir-x"), "arg: {arg}");
        }
    }

    #[test]
    fn branch_and_folder_agreeing_on_same_worktree_is_not_ambiguous() {
        // "plain" matches as branch AND as folder — same worktree, one result.
        let found = find(&fixture(), &root(), "plain", TargetKind::Any).unwrap();
        assert_eq!(found.path, Path::new("/r/.worktrees/plain"));
    }

    #[test]
    fn distinct_matches_are_an_error_listing_both() {
        // "confusing" is the branch of one worktree and the folder of another.
        let mut wts = fixture();
        wts.push(wt("/r/.worktrees/other", Some("confusing"), false));
        wts.push(wt("/r/.worktrees/confusing", Some("something-else"), false));

        let err = find(&wts, &root(), "confusing", TargetKind::Any)
            .unwrap_err()
            .to_string();
        assert!(err.contains("ambiguous"), "got: {err}");
        assert!(err.contains("/r/.worktrees/other"), "got: {err}");
        assert!(err.contains("/r/.worktrees/confusing"), "got: {err}");
        assert!(
            err.contains("--branch") && err.contains("--folder"),
            "should point at the disambiguation flags: {err}"
        );
    }

    #[test]
    fn no_match_errors_with_ls_hint() {
        let err = find(&fixture(), &root(), "nope", TargetKind::Any)
            .unwrap_err()
            .to_string();
        assert!(err.contains("no worktree 'nope'"), "got: {err}");
        assert!(err.contains("wt ls"), "got: {err}");
    }

    #[test]
    fn kind_branch_only_matches_branch() {
        assert!(find(&fixture(), &root(), "dir-x", TargetKind::Branch).is_err());
        assert!(find(&fixture(), &root(), "branch-x", TargetKind::Branch).is_ok());
    }

    #[test]
    fn kind_folder_only_matches_folder() {
        assert!(find(&fixture(), &root(), "branch-x", TargetKind::Folder).is_err());
        assert!(find(&fixture(), &root(), "dir-x", TargetKind::Folder).is_ok());
    }

    #[test]
    fn kind_path_only_matches_path() {
        assert!(find(&fixture(), &root(), "branch-x", TargetKind::Path).is_err());
        assert!(find(&fixture(), &root(), "dir-x", TargetKind::Path).is_err());
        assert!(find(&fixture(), &root(), "/r/.worktrees/dir-x", TargetKind::Path).is_ok());
    }

    #[test]
    fn main_checkout_is_never_a_target() {
        assert!(find(&fixture(), &root(), "main", TargetKind::Any).is_err());
        assert!(find(&fixture(), &root(), "/r", TargetKind::Any).is_err());
    }

    #[test]
    fn expand_home_rewrites_leading_tilde_only() {
        assert_eq!(
            expand_home("~/wts/x", Some("/home/u")),
            PathBuf::from("/home/u/wts/x")
        );
        assert_eq!(
            expand_home("/abs/x", Some("/home/u")),
            PathBuf::from("/abs/x")
        );
        assert_eq!(
            expand_home("rel/x", Some("/home/u")),
            PathBuf::from("rel/x")
        );
        // No HOME: leave the arg alone rather than guessing.
        assert_eq!(expand_home("~/wts/x", None), PathBuf::from("~/wts/x"));
    }

    #[test]
    fn normalize_strips_dots_and_trailing_slash() {
        assert_eq!(
            normalize(Path::new("/a/b/./c/../d/")),
            PathBuf::from("/a/b/d")
        );
        assert_eq!(normalize(Path::new("/a")), PathBuf::from("/a"));
    }
}
