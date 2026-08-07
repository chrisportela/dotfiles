//! Subprocess runner with dry-run support, ported from perviewerr.
//!
//! - `run`: mutating command; recorded (not executed) under --dry-run.
//! - `query`: read-only command; always executes, even under --dry-run, so
//!   plans can be computed from real state.
//! - `fs`: local filesystem mutation made dry-runnable; the description is
//!   recorded where an argv would be.

use std::path::Path;
use std::process::Command;

use anyhow::{Context, Result, bail};

#[cfg(test)]
type FakeExec = std::rc::Rc<dyn Fn(&str, &[&str]) -> Result<String>>;

pub struct Runner {
    pub dry_run: bool,
    planned: std::cell::RefCell<Vec<String>>,
    #[cfg(test)]
    fake: Option<FakeExec>,
}

fn render_argv(program: &str, args: &[&str]) -> String {
    std::iter::once(program)
        .chain(args.iter().copied())
        .map(|a| {
            if a.is_empty() || a.contains(char::is_whitespace) {
                format!("'{a}'")
            } else {
                a.to_string()
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

impl Runner {
    pub fn new(dry_run: bool) -> Self {
        Self {
            dry_run,
            planned: Default::default(),
            #[cfg(test)]
            fake: None,
        }
    }

    /// Test-only: every run/query is answered by `exec` instead of spawning a
    /// process; executed commands are still recorded in `planned`.
    #[cfg(test)]
    pub fn with_exec(exec: impl Fn(&str, &[&str]) -> Result<String> + 'static) -> Self {
        Self {
            dry_run: false,
            planned: Default::default(),
            fake: Some(std::rc::Rc::new(exec)),
        }
    }

    #[cfg(test)]
    fn fake_result(&self, program: &str, args: &[&str]) -> Option<Result<String>> {
        let fake = self.fake.as_ref()?;
        self.planned.borrow_mut().push(render_argv(program, args));
        Some(fake(program, args))
    }

    /// Commands recorded so far (all of them under `with_exec`; only
    /// non-executed ones under dry-run).
    #[cfg(test)]
    pub fn planned(&self) -> Vec<String> {
        self.planned.borrow().clone()
    }

    /// A local filesystem operation that must respect dry-run. `description`
    /// is what gets planned/printed in place of an argv.
    pub fn fs(&self, step: &str, description: &str, op: impl FnOnce() -> Result<()>) -> Result<()> {
        if self.dry_run {
            println!("[dry-run] {description}");
            self.planned.borrow_mut().push(description.to_string());
            return Ok(());
        }
        op().with_context(|| format!("step '{step}' failed: {description}"))
    }

    /// Read-only query: always executes, even in dry-run mode.
    pub fn query(
        &self,
        step: &str,
        program: &str,
        args: &[&str],
        cwd: Option<&Path>,
    ) -> Result<String> {
        #[cfg(test)]
        if let Some(result) = self.fake_result(program, args) {
            return result;
        }
        Runner::new(false).run(step, program, args, cwd)
    }

    /// Run `program` with `args`, optionally in `cwd`. Returns captured stdout.
    pub fn run(
        &self,
        step: &str,
        program: &str,
        args: &[&str],
        cwd: Option<&Path>,
    ) -> Result<String> {
        #[cfg(test)]
        if let Some(result) = self.fake_result(program, args) {
            return result;
        }
        let argv = match cwd {
            Some(dir) => format!("cd {} && {}", dir.display(), render_argv(program, args)),
            None => render_argv(program, args),
        };
        if self.dry_run {
            println!("[dry-run] {argv}");
            self.planned.borrow_mut().push(argv);
            return Ok(String::new());
        }
        let mut command = Command::new(program);
        command.args(args);
        if let Some(dir) = cwd {
            command.current_dir(dir);
        }
        let output = command
            .output()
            .with_context(|| format!("{step}: failed to spawn `{argv}`"))?;
        let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
        if std::env::var_os("WT_DEBUG").is_some() {
            eprintln!(
                "[wt debug] {argv} => {:?}\n  stdout: {:?}\n  stderr: {:?}",
                output.status,
                stdout,
                String::from_utf8_lossy(&output.stderr)
            );
        }
        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            let code = output
                .status
                .code()
                .map(|c| c.to_string())
                .unwrap_or_else(|| "signal".to_string());
            bail!(
                "step '{step}' failed: `{argv}` exited with exit code {code}\n\
                 --- stdout ---\n{stdout}\n--- stderr ---\n{stderr}"
            );
        }
        Ok(stdout)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dry_run_records_command_without_executing() {
        let dir = std::env::temp_dir().join("wt-cmd-dry-run-test");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let marker = dir.join("marker");
        let marker_arg = format!("touch {}", marker.display());

        let r = Runner::new(true);
        let out = r
            .run("create marker", "sh", &["-c", &marker_arg], None)
            .unwrap();

        assert!(!marker.exists(), "dry-run must not execute the command");
        assert_eq!(out, "");
        assert_eq!(r.planned(), vec![format!("sh -c '{}'", marker_arg)]);
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn fs_op_skipped_in_dry_run_and_executed_otherwise() {
        let dry = Runner::new(true);
        let mut ran = false;
        dry.fs("bootstrap env", "copy .env into worktree", || {
            ran = true;
            Ok(())
        })
        .unwrap();
        assert!(!ran, "dry-run must not execute fs ops");
        assert_eq!(dry.planned(), vec!["copy .env into worktree".to_string()]);

        let real = Runner::new(false);
        let mut ran = false;
        real.fs("bootstrap env", "copy .env into worktree", || {
            ran = true;
            Ok(())
        })
        .unwrap();
        assert!(ran);
    }

    #[test]
    fn failure_error_includes_step_argv_exit_code_and_output() {
        let r = Runner::new(false);
        let err = r
            .run(
                "fetch the branch",
                "sh",
                &["-c", "echo some-stdout; echo some-stderr >&2; exit 3"],
                None,
            )
            .unwrap_err();
        let msg = format!("{err:#}");
        assert!(msg.contains("fetch the branch"), "missing step name: {msg}");
        assert!(msg.contains("sh -c"), "missing argv: {msg}");
        assert!(msg.contains("exit code 3"), "missing exit code: {msg}");
        assert!(msg.contains("some-stdout"), "missing stdout: {msg}");
        assert!(msg.contains("some-stderr"), "missing stderr: {msg}");
    }

    #[test]
    fn run_captures_stdout_on_success() {
        let r = Runner::new(false);
        let out = r
            .run("echo test", "sh", &["-c", "echo hello"], None)
            .unwrap();
        assert_eq!(out.trim(), "hello");
    }

    #[test]
    fn query_executes_even_in_dry_run() {
        let r = Runner::new(true);
        let out = r
            .query("read value", "sh", &["-c", "echo live"], None)
            .unwrap();
        assert_eq!(out.trim(), "live");
    }
}
