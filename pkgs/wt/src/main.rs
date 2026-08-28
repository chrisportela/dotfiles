mod add;
mod cmd;
mod complete;
mod git;
mod init;
mod open;
mod prompt;
mod resolve;
mod rm;
mod setup;
mod tmux;

use anyhow::Result;
use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(
    name = "wt",
    about = "Git worktree manager: worktrees in .worktrees/, direnv setup, tmux automation",
    arg_required_else_help = true
)]
struct Cli {
    /// Print planned commands instead of executing mutations
    #[arg(long, global = true)]
    dry_run: bool,

    #[command(subcommand)]
    command: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Setup .worktrees/ and add it to .git/info/exclude
    Init,
    /// Create a worktree with a new or existing branch
    Add {
        /// Skip `direnv allow` / devshell priming
        #[arg(long)]
        no_direnv: bool,
        /// Skip copying .env files from the main checkout
        #[arg(long)]
        no_env: bool,
        /// Skip tmux window/pane creation
        #[arg(long)]
        no_tmux: bool,
        /// Create a detached tmux session instead of a window
        #[arg(long)]
        session: bool,
        branch: String,
    },
    /// Reopen tmux workspaces for existing worktrees (types `claude --continue`)
    Open {
        /// Create a detached tmux session instead of a window
        #[arg(long)]
        session: bool,
        /// Treat <TARGET> strictly as a branch name
        #[arg(long, requires = "target", conflicts_with_all = ["folder", "path"])]
        branch: bool,
        /// Treat <TARGET> strictly as a folder name under .worktrees/
        #[arg(long, requires = "target", conflicts_with = "path")]
        folder: bool,
        /// Treat <TARGET> strictly as a filesystem path
        #[arg(long, requires = "target")]
        path: bool,
        /// Worktree to open — branch name, .worktrees/ folder name, or path;
        /// omit to restore all worktrees
        target: Option<String>,
    },
    /// List active worktrees
    Ls,
    /// Remove a worktree interactively
    Rm {
        /// Skip killing the matching tmux window
        #[arg(long)]
        no_tmux: bool,
        /// Treat <TARGET> strictly as a branch name
        #[arg(long, conflicts_with_all = ["folder", "path"])]
        branch: bool,
        /// Treat <TARGET> strictly as a folder name under .worktrees/
        #[arg(long, conflicts_with = "path")]
        folder: bool,
        /// Treat <TARGET> strictly as a filesystem path
        #[arg(long)]
        path: bool,
        /// Worktree to remove — branch name, .worktrees/ folder name, or path
        target: String,
    },
    /// Shell-completion helper (prints candidates, one per line)
    #[command(name = "__complete", hide = true)]
    Complete {
        #[arg(value_parser = ["targets", "worktrees", "branches"])]
        what: String,
    },
}

fn target_kind(branch: bool, folder: bool, path: bool) -> resolve::TargetKind {
    match (branch, folder, path) {
        (true, _, _) => resolve::TargetKind::Branch,
        (_, true, _) => resolve::TargetKind::Folder,
        (_, _, true) => resolve::TargetKind::Path,
        _ => resolve::TargetKind::Any,
    }
}

fn run(cli: Cli) -> Result<()> {
    let runner = cmd::Runner::new(cli.dry_run);
    match cli.command {
        Cmd::Init => init::run(&runner),
        Cmd::Add {
            no_direnv,
            no_env,
            no_tmux,
            session,
            branch,
        } => add::run(
            &runner,
            &add::AddOpts {
                branch,
                no_direnv,
                no_env,
                no_tmux,
                session,
            },
        ),
        Cmd::Open {
            session,
            branch,
            folder,
            path,
            target,
        } => open::run(
            &runner,
            &open::OpenOpts {
                target,
                kind: target_kind(branch, folder, path),
                session,
            },
        ),
        Cmd::Ls => {
            let root = git::repo_root(&runner)?;
            let out = runner.query("list worktrees", "git", &["worktree", "list"], Some(&root))?;
            print!("{out}");
            Ok(())
        }
        Cmd::Rm {
            no_tmux,
            branch,
            folder,
            path,
            target,
        } => rm::run(
            &runner,
            &rm::RmOpts {
                target,
                kind: target_kind(branch, folder, path),
                no_tmux,
            },
        ),
        Cmd::Complete { what } => complete::run(&runner, &what),
    }
}

fn main() {
    if let Err(err) = run(Cli::parse()) {
        eprintln!("Error: {err:#}");
        std::process::exit(1);
    }
}
