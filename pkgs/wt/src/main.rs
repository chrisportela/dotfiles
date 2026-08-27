mod add;
mod cmd;
mod complete;
mod git;
mod init;
mod open;
mod prompt;
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
        /// Branch whose worktree to open; omit to restore all worktrees
        branch: Option<String>,
    },
    /// List active worktrees
    Ls,
    /// Remove a worktree interactively
    Rm {
        /// Skip killing the matching tmux window
        #[arg(long)]
        no_tmux: bool,
        branch: String,
    },
    /// Shell-completion helper (prints candidates, one per line)
    #[command(name = "__complete", hide = true)]
    Complete {
        #[arg(value_parser = ["worktrees", "branches"])]
        what: String,
    },
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
        Cmd::Open { session, branch } => open::run(&runner, &open::OpenOpts { branch, session }),
        Cmd::Ls => {
            let root = git::repo_root(&runner)?;
            let out = runner.query("list worktrees", "git", &["worktree", "list"], Some(&root))?;
            print!("{out}");
            Ok(())
        }
        Cmd::Rm { no_tmux, branch } => rm::run(
            &runner,
            &rm::RmOpts {
                name: branch,
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
