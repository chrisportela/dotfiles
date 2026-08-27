//! Hermetic end-to-end tests: a real git repo (local bare origin, no network)
//! in a tempdir, a private tmux server, and PATH shims for direnv/claude.
//! Set WT_IT_KEEP=1 to preserve a failed test's tempdir for post-mortem.

use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::sync::atomic::{AtomicU32, Ordering};

static FIXTURE_SEQ: AtomicU32 = AtomicU32::new(0);

struct Fixture {
    base: PathBuf,
    /// The main checkout.
    root: PathBuf,
    /// The ONLY directory on wt's PATH: a git symlink plus any logging shims
    /// a test installs. Keeps the host's real direnv/tmux/claude out of reach.
    bin: PathBuf,
    /// Private tmux server socket name, when `with_tmux()` was called.
    tmux_socket: Option<String>,
}

impl Fixture {
    fn new() -> Self {
        let seq = FIXTURE_SEQ.fetch_add(1, Ordering::SeqCst);
        let base = std::env::temp_dir().join(format!("wt-it-{}-{seq}", std::process::id()));
        let _ = std::fs::remove_dir_all(&base);
        std::fs::create_dir_all(&base).unwrap();
        let root = base.join("repo");

        let bin = base.join("bin");
        std::fs::create_dir_all(&bin).unwrap();
        let real_git = String::from_utf8(
            Command::new("sh")
                .args(["-c", "command -v git"])
                .output()
                .unwrap()
                .stdout,
        )
        .unwrap();
        std::os::unix::fs::symlink(real_git.trim(), bin.join("git")).unwrap();

        // Isolated git config: fixture HOME, no system config.
        std::fs::write(
            base.join(".gitconfig"),
            "[user]\n\tname = Test\n\temail = test@example.com\n[init]\n\tdefaultBranch = main\n",
        )
        .unwrap();

        let script = r#"
            set -e
            git init -q --bare origin.git
            git init -q repo
            cd repo
            git remote add origin ../origin.git
            echo readme > README.md
            git add README.md
            git commit -qm initial
            git push -q origin main
            # A remote-only branch for DWIM-tracking tests.
            git branch feature/x
            git push -q origin feature/x
            git branch -D feature/x
            git fetch -q origin
        "#;
        let out = Command::new("sh")
            .args(["-ec", script])
            .current_dir(&base)
            .env("HOME", &base)
            .env("GIT_CONFIG_NOSYSTEM", "1")
            .output()
            .unwrap();
        assert!(
            out.status.success(),
            "fixture git setup failed:\n{}",
            String::from_utf8_lossy(&out.stderr)
        );

        Fixture {
            base,
            root,
            bin,
            tmux_socket: None,
        }
    }

    /// Start a private tmux server with one session ("main") and route all of
    /// wt's tmux calls to it via WT_TMUX_SOCKET. default-shell is /bin/sh so
    /// pane shells start instantly and without user rc files.
    fn with_tmux(&mut self) {
        let real_tmux = String::from_utf8(
            Command::new("sh")
                .args(["-c", "command -v tmux"])
                .output()
                .unwrap()
                .stdout,
        )
        .unwrap();
        std::os::unix::fs::symlink(real_tmux.trim(), self.bin.join("tmux")).unwrap();

        let sock = self
            .base
            .file_name()
            .unwrap()
            .to_string_lossy()
            .into_owned();
        self.tmux_socket = Some(sock);
        self.tmux(&["new-session", "-d", "-x", "200", "-y", "50", "-s", "main"]);
        // Pin pane shells to a real sh from PATH: fast to start, no user rc
        // files, and not the sandbox's busybox /bin/sh (whose panes proved
        // flaky under the Nix build sandbox).
        let real_sh = String::from_utf8(
            Command::new("sh")
                .args(["-c", "command -v sh"])
                .output()
                .unwrap()
                .stdout,
        )
        .unwrap();
        self.tmux(&["set-option", "-g", "default-shell", real_sh.trim()]);
    }

    /// Run a tmux command against the private server (test-side helper).
    fn tmux(&self, args: &[&str]) -> String {
        let sock = self.tmux_socket.as_ref().expect("call with_tmux() first");
        let out = Command::new("tmux")
            .arg("-L")
            .arg(sock)
            .args(args)
            .output()
            .unwrap();
        assert!(
            out.status.success(),
            "tmux {args:?} failed:\n{}",
            String::from_utf8_lossy(&out.stderr)
        );
        String::from_utf8_lossy(&out.stdout).into_owned()
    }

    /// Poll until `pred` returns true (tmux state lands asynchronously).
    fn wait_until(&self, what: &str, mut pred: impl FnMut() -> bool) {
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(15);
        while std::time::Instant::now() < deadline {
            if pred() {
                return;
            }
            std::thread::sleep(std::time::Duration::from_millis(100));
        }
        panic!("timed out waiting for: {what}");
    }

    /// Install a logging shim on wt's PATH. The shim appends its argv to
    /// `<base>/<name>.log` and exits 0.
    fn install_shim(&self, name: &str) {
        let log = self.base.join(format!("{name}.log"));
        let script = format!("#!/bin/sh\nprintf '%s\\n' \"$*\" >> {}\n", log.display());
        let path = self.bin.join(name);
        std::fs::write(&path, script).unwrap();
        let mut perms = std::fs::metadata(&path).unwrap().permissions();
        std::os::unix::fs::PermissionsExt::set_mode(&mut perms, 0o755);
        std::fs::set_permissions(&path, perms).unwrap();
    }

    fn shim_log(&self, name: &str) -> String {
        std::fs::read_to_string(self.base.join(format!("{name}.log"))).unwrap_or_default()
    }

    /// The wt binary with a scrubbed, fixture-scoped environment, cwd `dir`.
    fn wt_in(&self, dir: &Path, args: &[&str]) -> Command {
        let mut c = Command::new(env!("CARGO_BIN_EXE_wt"));
        c.args(args)
            .current_dir(dir)
            .env("PATH", &self.bin)
            .env("HOME", &self.base)
            .env("WT_DEBUG", "1")
            .env("GIT_CONFIG_NOSYSTEM", "1")
            .env_remove("TMUX")
            .env_remove("GIT_DIR")
            .env_remove("GIT_WORK_TREE");
        if let Some(sock) = &self.tmux_socket {
            c.env("WT_TMUX_SOCKET", sock);
        }
        c
    }

    fn wt(&self, args: &[&str]) -> Command {
        self.wt_in(&self.root.clone(), args)
    }

    fn run_wt(&self, args: &[&str]) -> Output {
        self.wt(args).output().unwrap()
    }

    /// Run wt with the given lines piped to stdin (for `rm` prompts).
    fn run_wt_stdin(&self, args: &[&str], input: &str) -> Output {
        use std::io::Write;
        let mut child = self
            .wt(args)
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn()
            .unwrap();
        child
            .stdin
            .take()
            .unwrap()
            .write_all(input.as_bytes())
            .unwrap();
        child.wait_with_output().unwrap()
    }

    fn exclude_file(&self) -> PathBuf {
        self.root.join(".git/info/exclude")
    }

    /// Run a git command in the main checkout with the fixture env.
    fn git(&self, args: &[&str]) {
        let out = Command::new("git")
            .args(args)
            .current_dir(&self.root)
            .env("HOME", &self.base)
            .env("GIT_CONFIG_NOSYSTEM", "1")
            .output()
            .unwrap();
        assert!(
            out.status.success(),
            "git {args:?} failed:\n{}",
            String::from_utf8_lossy(&out.stderr)
        );
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        if let Some(sock) = &self.tmux_socket {
            let _ = Command::new("tmux")
                .args(["-L", sock, "kill-server"])
                .output();
        }
        if std::env::var_os("WT_IT_KEEP").is_some() {
            eprintln!(
                "WT_IT_KEEP set — fixture preserved at {}",
                self.base.display()
            );
            return;
        }
        let _ = std::fs::remove_dir_all(&self.base);
    }
}

fn stdout_of(out: &Output) -> String {
    String::from_utf8_lossy(&out.stdout).into_owned()
}

fn stderr_of(out: &Output) -> String {
    String::from_utf8_lossy(&out.stderr).into_owned()
}

fn assert_success(out: &Output) {
    assert!(
        out.status.success(),
        "wt failed (exit {:?})\n--- stdout ---\n{}\n--- stderr ---\n{}",
        out.status.code(),
        stdout_of(out),
        stderr_of(out)
    );
}

#[test]
fn bare_wt_prints_usage() {
    let out = Command::new(env!("CARGO_BIN_EXE_wt")).output().unwrap();
    let all = format!(
        "{}{}",
        String::from_utf8_lossy(&out.stdout),
        String::from_utf8_lossy(&out.stderr)
    );
    assert!(all.contains("Usage"), "expected usage text, got: {all}");
    for cmd in ["init", "add", "open", "ls", "rm"] {
        assert!(all.contains(cmd), "usage should mention '{cmd}': {all}");
    }
    assert!(
        !all.contains("__complete"),
        "hidden helper must not appear in help: {all}"
    );
}

#[test]
fn init_creates_worktrees_dir_and_exclude_entry() {
    let f = Fixture::new();

    let out = f.run_wt(&["init"]);
    assert_success(&out);

    assert!(f.root.join(".worktrees").is_dir());
    let exclude = std::fs::read_to_string(f.exclude_file()).unwrap();
    assert!(
        exclude.lines().any(|l| l == ".worktrees/"),
        "exclude should contain .worktrees/: {exclude}"
    );
    assert!(stdout_of(&out).contains("Created .worktrees/"));
}

#[test]
fn init_is_idempotent() {
    let f = Fixture::new();

    assert_success(&f.run_wt(&["init"]));
    let out = f.run_wt(&["init"]);
    assert_success(&out);

    let exclude = std::fs::read_to_string(f.exclude_file()).unwrap();
    let entries = exclude
        .lines()
        .filter(|l| l.starts_with(".worktrees"))
        .count();
    assert_eq!(
        entries, 1,
        "exclude must not accumulate duplicates: {exclude}"
    );
    assert!(stdout_of(&out).contains("already"));
}

#[test]
fn complete_worktrees_lists_full_slashed_names_of_registered_worktrees_only() {
    let f = Fixture::new();
    assert_success(&f.run_wt(&["init"]));

    f.git(&[
        "worktree",
        "add",
        "-b",
        "cportela/feature-y",
        ".worktrees/cportela/feature-y",
    ]);
    f.git(&["worktree", "add", "-b", "flat", ".worktrees/flat"]);
    // A stale directory that is NOT a registered worktree (the old completion
    // bug offered these).
    std::fs::create_dir_all(f.root.join(".worktrees/stale-container")).unwrap();

    let out = f.run_wt(&["__complete", "worktrees"]);
    assert_success(&out);
    let stdout = stdout_of(&out);
    let mut lines: Vec<&str> = stdout.lines().collect();
    lines.sort();
    assert_eq!(
        lines,
        vec!["cportela/feature-y", "flat"],
        "must list full slashed names, no stale dirs, no main checkout"
    );
}

#[test]
fn complete_branches_offers_local_and_remote_but_not_checked_out() {
    let f = Fixture::new();
    f.git(&["branch", "dev"]);

    let out = f.run_wt(&["__complete", "branches"]);
    assert_success(&out);
    let stdout = stdout_of(&out);
    let lines: Vec<&str> = stdout.lines().collect();
    assert!(lines.contains(&"dev"), "local branch missing: {lines:?}");
    assert!(
        lines.contains(&"feature/x"),
        "remote-only branch missing: {lines:?}"
    );
    assert!(
        !lines.contains(&"main"),
        "checked-out branch must be excluded: {lines:?}"
    );
    assert!(!lines.contains(&"HEAD"), "HEAD must be excluded: {lines:?}");
    assert_eq!(
        lines.iter().filter(|l| **l == "dev").count(),
        1,
        "no duplicates: {lines:?}"
    );
}

#[test]
fn complete_outside_repo_is_silent_success() {
    let f = Fixture::new();
    let outside = f.base.join("outside");
    std::fs::create_dir_all(&outside).unwrap();

    let out = f
        .wt_in(&outside, &["__complete", "worktrees"])
        .output()
        .unwrap();
    assert!(out.status.success(), "completion must never error");
    assert_eq!(stdout_of(&out), "");
}

#[test]
fn add_checks_out_existing_local_branch() {
    let f = Fixture::new();
    f.git(&["branch", "dev"]);

    let out = f.run_wt(&["add", "dev"]);
    assert_success(&out);
    assert!(stdout_of(&out).contains("existing branch 'dev'"));
    assert!(stdout_of(&out).contains("Worktree ready at: .worktrees/dev"));

    let wt = f.root.join(".worktrees/dev");
    assert!(wt.is_dir());
    let head = Command::new("git")
        .args(["branch", "--show-current"])
        .current_dir(&wt)
        .output()
        .unwrap();
    assert_eq!(String::from_utf8_lossy(&head.stdout).trim(), "dev");
}

#[test]
fn add_tracks_unique_remote_branch_with_nested_path() {
    let f = Fixture::new();

    let out = f.run_wt(&["add", "feature/x"]);
    assert_success(&out);
    assert!(
        stdout_of(&out).contains("Tracking remote branch 'origin/feature/x'"),
        "got: {}",
        stdout_of(&out)
    );

    assert!(f.root.join(".worktrees/feature/x").is_dir());
    let upstream = Command::new("git")
        .args(["rev-parse", "--abbrev-ref", "feature/x@{upstream}"])
        .current_dir(&f.root)
        .env("HOME", &f.base)
        .env("GIT_CONFIG_NOSYSTEM", "1")
        .output()
        .unwrap();
    assert_eq!(
        String::from_utf8_lossy(&upstream.stdout).trim(),
        "origin/feature/x"
    );
}

#[test]
fn add_creates_new_branch_when_unknown_and_auto_inits() {
    let f = Fixture::new();
    // No `wt init` first — add must auto-init.

    let out = f.run_wt(&["add", "brand-new"]);
    assert_success(&out);
    assert!(stdout_of(&out).contains("new branch 'brand-new'"));

    assert!(f.root.join(".worktrees/brand-new").is_dir());
    let exclude = std::fs::read_to_string(f.exclude_file()).unwrap();
    assert!(exclude.lines().any(|l| l == ".worktrees/"));
}

#[test]
fn add_errors_when_branch_exists_on_multiple_remotes() {
    let f = Fixture::new();
    f.git(&["remote", "add", "origin2", "../origin.git"]);
    f.git(&["fetch", "-q", "origin2"]);

    let out = f.run_wt(&["add", "feature/x"]);
    assert!(!out.status.success());
    let err = stderr_of(&out);
    assert!(err.contains("origin/feature/x"), "got: {err}");
    assert!(err.contains("origin2/feature/x"), "got: {err}");
}

#[test]
fn add_errors_when_branch_already_checked_out() {
    let f = Fixture::new();

    let out = f.run_wt(&["add", "main"]);
    assert!(!out.status.success());
    let err = stderr_of(&out);
    assert!(
        err.contains("already checked out") && err.contains("repo"),
        "error should name the existing checkout path: {err}"
    );
}

#[test]
fn add_errors_on_stale_unregistered_directory() {
    let f = Fixture::new();
    assert_success(&f.run_wt(&["init"]));
    std::fs::create_dir_all(f.root.join(".worktrees/stale")).unwrap();

    let out = f.run_wt(&["add", "stale"]);
    assert!(!out.status.success());
    assert!(
        stderr_of(&out).contains("git worktree prune"),
        "should hint at prune: {}",
        stderr_of(&out)
    );
}

/// Repo shape for setup tests: an excluded .envrc, an untracked .env, and a
/// tracked src/.envrc (which git materializes in worktrees by itself).
fn prepare_env_files(f: &Fixture) {
    std::fs::write(f.root.join(".envrc"), "use flake\n").unwrap();
    std::fs::write(f.root.join(".env"), "SECRET=1\n").unwrap();
    std::fs::create_dir_all(f.root.join("src")).unwrap();
    std::fs::write(f.root.join("src/.envrc"), "dotenv\n").unwrap();
    // Anchored so only the ROOT .envrc is excluded (an unanchored `.envrc`
    // would also ignore src/.envrc, which we want tracked).
    // .env stays plain-untracked; both must be copied.
    std::fs::write(f.exclude_file(), "/.envrc\n").unwrap();
    f.git(&["add", "src/.envrc"]);
    f.git(&["commit", "-qm", "add tracked nested envrc"]);
}

#[test]
fn add_copies_env_files_and_allows_then_primes_direnv() {
    let f = Fixture::new();
    f.install_shim("direnv");
    prepare_env_files(&f);

    let out = f.run_wt(&["add", "setup-test"]);
    assert_success(&out);

    let wt = f.root.join(".worktrees/setup-test");
    assert_eq!(
        std::fs::read_to_string(wt.join(".envrc")).unwrap(),
        "use flake\n",
        "excluded .envrc must be copied from the main checkout"
    );
    assert_eq!(
        std::fs::read_to_string(wt.join(".env")).unwrap(),
        "SECRET=1\n",
        "untracked .env must be copied"
    );
    assert!(
        wt.join("src/.envrc").is_file(),
        "tracked .envrc comes from git"
    );

    let log = f.shim_log("direnv");
    let lines: Vec<&str> = log.lines().collect();
    let allow_root = lines
        .iter()
        .position(|l| *l == format!("allow {}", wt.join(".envrc").display()))
        .unwrap_or_else(|| panic!("no allow for root .envrc in log:\n{log}"));
    let allow_nested = lines
        .iter()
        .position(|l| *l == format!("allow {}", wt.join("src/.envrc").display()))
        .unwrap_or_else(|| panic!("no allow for src/.envrc in log:\n{log}"));
    let prime = lines
        .iter()
        .position(|l| *l == format!("exec {} true", wt.display()))
        .unwrap_or_else(|| panic!("no direnv exec prime in log:\n{log}"));
    assert!(allow_root < allow_nested, "allows must be sorted: {log}");
    assert!(
        allow_nested < prime,
        "all allows must precede the prime: {log}"
    );

    assert!(stdout_of(&out).contains("allowed: .envrc"));
    assert!(stdout_of(&out).contains("allowed: src/.envrc"));
}

#[test]
fn add_no_env_skips_env_copy_but_still_copies_envrc() {
    let f = Fixture::new();
    f.install_shim("direnv");
    prepare_env_files(&f);

    assert_success(&f.run_wt(&["add", "--no-env", "skip-env"]));

    let wt = f.root.join(".worktrees/skip-env");
    assert!(
        !wt.join(".env").exists(),
        ".env must not be copied with --no-env"
    );
    assert!(
        wt.join(".envrc").is_file(),
        ".envrc copy is independent of --no-env"
    );
}

#[test]
fn add_no_direnv_skips_allow_and_prime() {
    let f = Fixture::new();
    f.install_shim("direnv");
    prepare_env_files(&f);

    assert_success(&f.run_wt(&["add", "--no-direnv", "skip-direnv"]));

    assert_eq!(f.shim_log("direnv"), "", "direnv must not be invoked");
    assert!(
        f.root.join(".worktrees/skip-direnv/.envrc").is_file(),
        "file copies still happen with --no-direnv"
    );
}

#[test]
fn add_without_direnv_on_path_is_silently_fine() {
    let f = Fixture::new(); // no direnv shim installed
    prepare_env_files(&f);

    let out = f.run_wt(&["add", "no-direnv-installed"]);
    assert_success(&out);
    assert!(!stdout_of(&out).contains("Approving"));
}

#[test]
fn add_creates_tmux_window_with_titled_panes_and_typed_unentered_claude() {
    let mut f = Fixture::new();
    f.with_tmux();
    f.install_shim("claude"); // logs if `claude` is ever EXECUTED — it must not be

    let out = f.run_wt(&["add", "feature/x"]);
    assert_success(&out);
    // Shown only when a later assertion fails — tells us which tmux branch
    // wt actually took (created / reused / skipped).
    eprintln!("wt stdout:\n{}", stdout_of(&out));
    eprintln!("wt stderr:\n{}", stderr_of(&out));
    let wt = f.root.join(".worktrees/feature/x");

    // Window named after the branch, slashes intact.
    let windows = f.tmux(&[
        "list-windows",
        "-a",
        "-F",
        "#{session_name}|#{window_id}|#{window_name}",
    ]);
    assert!(
        windows.lines().any(|w| w.ends_with("|feature/x")),
        "no window named feature/x: {windows}"
    );

    // Two panes, titled claude + shell, both cwd'd to the worktree.
    // '|' separator: some tmux versions sanitize tabs in command output to '_'.
    let panes = f.tmux(&[
        "list-panes",
        "-t",
        "main:feature/x",
        "-F",
        "#{pane_id}|#{pane_title}|#{pane_current_path}",
    ]);
    let rows: Vec<Vec<&str>> = panes
        .lines()
        .map(|l| l.split('|').collect::<Vec<_>>())
        .collect();
    assert!(
        rows.len() == 2 && rows.iter().all(|r| r.len() == 3),
        "expected 2 well-formed panes, got:\n{panes}\nall windows:\n{windows}"
    );
    let titles: Vec<&str> = rows.iter().map(|r| r[1]).collect();
    assert_eq!(titles, vec!["claude", "shell"], "pane titles: {panes}");
    for row in &rows {
        assert_eq!(
            std::fs::canonicalize(row[2]).unwrap(),
            std::fs::canonicalize(&wt).unwrap(),
            "pane cwd must be the worktree: {panes}"
        );
    }

    // The claude pane has the literal text `claude` typed but NOT run.
    let claude_pane = rows[0][0].to_string();
    f.wait_until("typed 'claude' visible in pane", || {
        f.tmux(&["capture-pane", "-p", "-t", &claude_pane])
            .lines()
            .any(|l| l.contains("claude"))
    });
    std::thread::sleep(std::time::Duration::from_millis(300));
    assert_eq!(
        f.shim_log("claude"),
        "",
        "claude must be typed, never executed (was Enter sent?)"
    );
}

#[test]
fn add_session_creates_detached_session_with_sanitized_name() {
    let mut f = Fixture::new();
    f.with_tmux();
    f.git(&["branch", "rel/v1.2"]);

    let out = f.run_wt(&["add", "--session", "rel/v1.2"]);
    assert_success(&out);

    // '/' and '.' are tmux-hostile in session names → sanitized.
    let sessions = f.tmux(&["list-sessions", "-F", "#{session_name}"]);
    assert!(
        sessions.lines().any(|s| s == "rel-v1-2"),
        "expected session rel-v1-2: {sessions}"
    );
    // Window inside keeps the real branch name.
    let windows = f.tmux(&["list-windows", "-t", "=rel-v1-2:", "-F", "#{window_name}"]);
    assert!(windows.lines().any(|w| w == "rel/v1.2"), "got: {windows}");
    assert!(
        stdout_of(&out).contains("tmux attach -t rel-v1-2"),
        "attach hint missing: {}",
        stdout_of(&out)
    );
}

#[test]
fn add_no_tmux_creates_no_window() {
    let mut f = Fixture::new();
    f.with_tmux();

    assert_success(&f.run_wt(&["add", "--no-tmux", "quiet"]));

    let windows = f.tmux(&["list-windows", "-a", "-F", "#{window_name}"]);
    assert!(
        !windows.lines().any(|w| w == "quiet"),
        "--no-tmux must not create a window: {windows}"
    );
}

#[test]
fn add_outside_tmux_skips_window_with_note() {
    let f = Fixture::new(); // no with_tmux(): no TMUX, no WT_TMUX_SOCKET

    let out = f.run_wt(&["add", "outside"]);
    assert_success(&out);
    assert!(
        stdout_of(&out).contains("not inside tmux"),
        "expected a skip note: {}",
        stdout_of(&out)
    );
}

#[test]
fn add_reuses_existing_window_of_same_name() {
    let mut f = Fixture::new();
    f.with_tmux();
    f.tmux(&["new-window", "-d", "-t", "main:", "-n", "dup"]);

    let out = f.run_wt(&["add", "dup"]);
    assert_success(&out);
    eprintln!("wt stdout:\n{}", stdout_of(&out));
    eprintln!("wt stderr:\n{}", stderr_of(&out));

    let windows = f.tmux(&["list-windows", "-a", "-F", "#{window_name}"]);
    assert_eq!(
        windows.lines().filter(|w| *w == "dup").count(),
        1,
        "must reuse, not duplicate: {windows}"
    );
    assert!(
        stdout_of(&out).contains("already exists"),
        "expected a reuse note: {}",
        stdout_of(&out)
    );
}

#[test]
fn open_reopens_window_typing_claude_continue_unentered() {
    let mut f = Fixture::new();
    f.with_tmux();
    f.install_shim("claude"); // logs if `claude` is ever EXECUTED — it must not be
    assert_success(&f.run_wt(&["add", "--no-tmux", "feature/x"]));

    let out = f.run_wt(&["open", "feature/x"]);
    assert_success(&out);
    eprintln!("wt stdout:\n{}", stdout_of(&out));
    eprintln!("wt stderr:\n{}", stderr_of(&out));

    let panes = f.tmux(&[
        "list-panes",
        "-t",
        "main:feature/x",
        "-F",
        "#{pane_id}|#{pane_title}",
    ]);
    let rows: Vec<Vec<&str>> = panes
        .lines()
        .map(|l| l.split('|').collect::<Vec<_>>())
        .collect();
    let titles: Vec<&str> = rows.iter().map(|r| r[1]).collect();
    assert_eq!(titles, vec!["claude", "shell"], "pane titles: {panes}");

    // The resume command is typed but NOT run. -J joins wrapped lines: the
    // long fixture prompt can push the typed text across the wrap boundary.
    let claude_pane = rows[0][0].to_string();
    f.wait_until("typed 'claude --continue' visible in pane", || {
        f.tmux(&["capture-pane", "-p", "-J", "-t", &claude_pane])
            .lines()
            .any(|l| l.contains("claude --continue"))
    });
    std::thread::sleep(std::time::Duration::from_millis(300));
    assert_eq!(
        f.shim_log("claude"),
        "",
        "claude must be typed, never executed (was Enter sent?)"
    );
}

#[test]
fn open_twice_reuses_the_window() {
    let mut f = Fixture::new();
    f.with_tmux();
    assert_success(&f.run_wt(&["add", "--no-tmux", "again"]));

    assert_success(&f.run_wt(&["open", "again"]));
    let out = f.run_wt(&["open", "again"]);
    assert_success(&out);

    let windows = f.tmux(&["list-windows", "-a", "-F", "#{window_name}"]);
    assert_eq!(
        windows.lines().filter(|w| *w == "again").count(),
        1,
        "must reuse, not duplicate: {windows}"
    );
    assert!(
        stdout_of(&out).contains("already exists"),
        "expected a reuse note: {}",
        stdout_of(&out)
    );
}

#[test]
fn open_unknown_worktree_is_clean_error_with_add_hint() {
    let f = Fixture::new();
    assert_success(&f.run_wt(&["init"]));

    let out = f.run_wt(&["open", "nope"]);
    assert!(!out.status.success());
    let err = stderr_of(&out);
    assert!(err.contains("no worktree"), "got: {err}");
    assert!(err.contains("wt add"), "should hint at wt add: {err}");
}

#[test]
fn open_restore_all_opens_closed_worktrees_and_skips_open_ones() {
    let mut f = Fixture::new();
    f.with_tmux();
    assert_success(&f.run_wt(&["add", "--no-tmux", "alpha"])); // no window yet
    assert_success(&f.run_wt(&["add", "beta"])); // window already open

    let out = f.run_wt(&["open"]);
    assert_success(&out);
    eprintln!("wt stdout:\n{}", stdout_of(&out));
    eprintln!("wt stderr:\n{}", stderr_of(&out));

    let windows = f.tmux(&["list-windows", "-a", "-F", "#{window_name}"]);
    for name in ["alpha", "beta"] {
        assert_eq!(
            windows.lines().filter(|w| *w == name).count(),
            1,
            "expected exactly one '{name}' window: {windows}"
        );
    }
    assert!(
        stdout_of(&out).contains("already open"),
        "expected a skip note for beta: {}",
        stdout_of(&out)
    );
}

#[test]
fn open_session_creates_detached_session_typing_claude_continue() {
    let mut f = Fixture::new();
    f.with_tmux();
    f.git(&["branch", "rel/v1.2"]);
    assert_success(&f.run_wt(&["add", "--no-tmux", "rel/v1.2"]));

    let out = f.run_wt(&["open", "--session", "rel/v1.2"]);
    assert_success(&out);

    let sessions = f.tmux(&["list-sessions", "-F", "#{session_name}"]);
    assert!(
        sessions.lines().any(|s| s == "rel-v1-2"),
        "expected session rel-v1-2: {sessions}"
    );
    assert!(
        stdout_of(&out).contains("tmux attach -t rel-v1-2"),
        "attach hint missing: {}",
        stdout_of(&out)
    );
}

#[test]
fn rm_merges_and_deletes_branch_on_confirm() {
    let f = Fixture::new();
    assert_success(&f.run_wt(&["add", "feature-z"]));
    let wt = f.root.join(".worktrees/feature-z");
    std::fs::write(wt.join("new-file.txt"), "hi\n").unwrap();
    let commit = Command::new("sh")
        .args(["-ec", "git add new-file.txt && git commit -qm work"])
        .current_dir(&wt)
        .env("HOME", &f.base)
        .env("GIT_CONFIG_NOSYSTEM", "1")
        .output()
        .unwrap();
    assert!(commit.status.success());

    // merge? y — delete? default yes (empty line)
    let out = f.run_wt_stdin(&["rm", "feature-z"], "y\n\n");
    assert_success(&out);

    assert!(!wt.exists(), "worktree dir must be removed");
    assert!(
        f.root.join("new-file.txt").is_file(),
        "merge must land on main"
    );
    let branches = Command::new("git")
        .args(["branch", "--list", "feature-z"])
        .current_dir(&f.root)
        .output()
        .unwrap();
    assert_eq!(
        String::from_utf8_lossy(&branches.stdout).trim(),
        "",
        "branch must be deleted"
    );
    assert!(stdout_of(&out).contains("Merged 'feature-z'"));
    assert!(stdout_of(&out).contains("Deleted branch 'feature-z'"));
}

#[test]
fn rm_dirty_aborts_without_force() {
    let f = Fixture::new();
    assert_success(&f.run_wt(&["add", "dirty-branch"]));
    let wt = f.root.join(".worktrees/dirty-branch");
    std::fs::write(wt.join("uncommitted.txt"), "wip\n").unwrap();

    let out = f.run_wt_stdin(&["rm", "dirty-branch"], "n\n");
    assert_success(&out); // abort is exit 0, matching the bash version
    assert!(wt.exists(), "worktree must survive an aborted rm");
    assert!(
        stdout_of(&out).contains("uncommitted.txt"),
        "dirty files listed"
    );
    assert!(stdout_of(&out).contains("Aborted"));
}

#[test]
fn rm_dirty_force_removes_and_can_keep_branch() {
    let f = Fixture::new();
    assert_success(&f.run_wt(&["add", "keep-me"]));
    let wt = f.root.join(".worktrees/keep-me");
    std::fs::write(wt.join("uncommitted.txt"), "wip\n").unwrap();

    // force? y — merge? n — delete? n
    let out = f.run_wt_stdin(&["rm", "keep-me"], "y\nn\nn\n");
    assert_success(&out);
    assert!(!wt.exists());
    let branches = Command::new("git")
        .args(["branch", "--list", "keep-me"])
        .current_dir(&f.root)
        .output()
        .unwrap();
    assert!(
        String::from_utf8_lossy(&branches.stdout).contains("keep-me"),
        "branch must be kept"
    );
}

#[test]
fn rm_cleans_empty_container_directories() {
    let f = Fixture::new();
    assert_success(&f.run_wt(&["add", "cportela/tmp"]));
    assert!(f.root.join(".worktrees/cportela/tmp").is_dir());

    // merge? n — delete? default yes
    let out = f.run_wt_stdin(&["rm", "cportela/tmp"], "n\n\n");
    assert_success(&out);

    assert!(
        !f.root.join(".worktrees/cportela").exists(),
        "emptied container dir must be cleaned up"
    );
    assert!(
        f.root.join(".worktrees").is_dir(),
        ".worktrees itself must survive"
    );
}

#[test]
fn rm_gone_upstream_recommends_force_delete() {
    let f = Fixture::new();
    assert_success(&f.run_wt(&["add", "feature/x"]));
    let wt = f.root.join(".worktrees/feature/x");
    std::fs::write(wt.join("ahead.txt"), "x\n").unwrap();
    let commit = Command::new("sh")
        .args(["-ec", "git add ahead.txt && git commit -qm ahead"])
        .current_dir(&wt)
        .env("HOME", &f.base)
        .env("GIT_CONFIG_NOSYSTEM", "1")
        .output()
        .unwrap();
    assert!(commit.status.success());
    // Simulate a squash-merge: remote branch deleted.
    f.git(&["push", "-q", "origin", "--delete", "feature/x"]);
    f.git(&["fetch", "-q", "--prune", "origin"]);

    // merge? n — delete? default yes (-d fails) — force? default yes
    let out = f.run_wt_stdin(&["rm", "feature/x"], "n\n\n\n");
    assert_success(&out);
    assert!(stdout_of(&out).contains("Recommending force delete"));
    let branches = Command::new("git")
        .args(["branch", "--list", "feature/x"])
        .current_dir(&f.root)
        .output()
        .unwrap();
    assert_eq!(String::from_utf8_lossy(&branches.stdout).trim(), "");
}

#[test]
fn rm_unknown_worktree_is_clean_error() {
    let f = Fixture::new();
    assert_success(&f.run_wt(&["init"]));
    // A container dir alone (the old bug: completion offered these and rm blew up).
    std::fs::create_dir_all(f.root.join(".worktrees/cportela")).unwrap();

    let out = f.run_wt_stdin(&["rm", "cportela"], "");
    assert!(!out.status.success());
    assert!(
        stderr_of(&out).contains("no worktree 'cportela'"),
        "got: {}",
        stderr_of(&out)
    );
}

#[test]
fn rm_kills_tmux_window_after_confirm() {
    let mut f = Fixture::new();
    f.with_tmux();
    assert_success(&f.run_wt(&["add", "feature/x"]));
    assert!(
        f.tmux(&["list-windows", "-a", "-F", "#{window_name}"])
            .lines()
            .any(|w| w == "feature/x")
    );

    // merge? n — delete? n — kill window? default yes
    let out = f.run_wt_stdin(&["rm", "feature/x"], "n\nn\n\n");
    assert_success(&out);
    eprintln!("wt stdout:\n{}", stdout_of(&out));
    eprintln!("wt stderr:\n{}", stderr_of(&out));
    f.wait_until("window feature/x gone", || {
        !f.tmux(&["list-windows", "-a", "-F", "#{window_name}"])
            .lines()
            .any(|w| w == "feature/x")
    });
}

#[test]
fn ls_passes_through_git_worktree_list() {
    let f = Fixture::new();
    assert_success(&f.run_wt(&["add", "listed"]));

    let out = f.run_wt(&["ls"]);
    assert_success(&out);
    let stdout = stdout_of(&out);
    assert!(stdout.contains(".worktrees/listed"), "got: {stdout}");
    // Two lines: main checkout + the new worktree.
    assert_eq!(stdout.lines().count(), 2, "got: {stdout}");
}

#[test]
fn dry_run_plans_in_order_and_changes_nothing() {
    let mut f = Fixture::new();
    f.with_tmux();
    f.install_shim("direnv");
    prepare_env_files(&f);
    let windows_before = f.tmux(&["list-windows", "-a", "-F", "#{window_name}"]);

    let out = f.run_wt(&["--dry-run", "add", "planned"]);
    assert_success(&out);
    let stdout = stdout_of(&out);

    // Nothing actually happened.
    assert!(!f.root.join(".worktrees/planned").exists());
    assert_eq!(
        f.tmux(&["list-windows", "-a", "-F", "#{window_name}"]),
        windows_before
    );
    assert_eq!(f.shim_log("direnv"), "");

    // Recorded mutations appear in dependency order. (direnv allow/prime are
    // absent by design: they enumerate .envrc files inside the not-yet-created
    // worktree, so a dry-run has nothing to record for them.)
    let pos = |needle: &str| {
        stdout
            .lines()
            .position(|l| l.starts_with("[dry-run]") && l.contains(needle))
            .unwrap_or_else(|| panic!("no dry-run line containing {needle:?}:\n{stdout}"))
    };
    let worktree_add = pos("worktree add");
    let copy_envrc = pos("copy .envrc");
    let copy_env = pos("copy .env into");
    let new_window = pos("new-window");
    let split = pos("split-window");
    let title = pos("select-pane");
    let send_keys = pos("send-keys");
    assert!(worktree_add < copy_envrc, "{stdout}");
    assert!(copy_envrc < copy_env, "{stdout}");
    assert!(copy_env < new_window, "{stdout}");
    assert!(new_window < split, "{stdout}");
    assert!(split < title, "{stdout}");
    assert!(title < send_keys, "{stdout}");
    assert!(
        !stdout.contains("Enter"),
        "send-keys must not press Enter: {stdout}"
    );
}

#[test]
fn not_in_a_git_repo_is_a_clean_error() {
    let f = Fixture::new();
    let outside = f.base.join("outside");
    std::fs::create_dir_all(&outside).unwrap();

    let out = f.wt_in(&outside, &["init"]).output().unwrap();
    assert!(!out.status.success());
    assert!(
        stderr_of(&out).contains("not in a git repository"),
        "got: {}",
        stderr_of(&out)
    );
}
