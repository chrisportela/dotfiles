{
  writeShellApplication,
  git,
  coreutils,
}:

writeShellApplication {
  name = "wt";

  runtimeInputs = [
    git
    coreutils
  ];

  text = ''
    WORKTREE_DIR=".worktrees"

    usage() {
      echo "Usage: wt <command> [args]"
      echo ""
      echo "Commands:"
      echo "  init          Setup .worktrees/ and add to .git/info/exclude"
      echo "  add <branch>  Create a worktree with a new or existing branch"
      echo "  ls            List active worktrees"
      echo "  rm <branch>   Remove a worktree interactively"
      echo "  help          Show this help message"
    }

    ensure_git_repo() {
      if ! git rev-parse --show-toplevel &>/dev/null; then
        echo "Error: Not in a git repository" >&2
        exit 1
      fi
    }

    get_root() {
      git rev-parse --show-toplevel
    }

    cmd_init() {
      ensure_git_repo
      local root
      root="$(get_root)"
      local wt_path="$root/$WORKTREE_DIR"

      # Create .worktrees directory
      if [ -d "$wt_path" ]; then
        echo ".worktrees/ already exists"
      else
        mkdir -p "$wt_path"
        echo "Created .worktrees/"
      fi

      # Add to .git/info/exclude
      local exclude="$root/.git/info/exclude"
      mkdir -p "$root/.git/info"
      touch "$exclude"

      if ! grep -q "^\.worktrees/?$\|^\.worktrees$" "$exclude" 2>/dev/null; then
        echo ".worktrees/" >> "$exclude"
        echo "Added .worktrees/ to .git/info/exclude"
      else
        echo ".worktrees/ already in .git/info/exclude"
      fi
    }

    cmd_add() {
      local branch="''${1:-}"
      if [ -z "$branch" ]; then
        echo "Usage: wt add <branch>" >&2
        exit 1
      fi

      ensure_git_repo
      local root
      root="$(get_root)"
      local wt_path="$root/$WORKTREE_DIR/$branch"

      # Auto-init if needed
      if [ ! -d "$root/$WORKTREE_DIR" ]; then
        cmd_init
      fi

      if [ -d "$wt_path" ]; then
        echo "Error: Worktree already exists at $WORKTREE_DIR/$branch" >&2
        exit 1
      fi

      # Check if branch already exists
      if git show-ref --verify --quiet "refs/heads/$branch"; then
        echo "Checking out existing branch '$branch'"
        git worktree add "$wt_path" "$branch"
      else
        echo "Creating new branch '$branch'"
        git worktree add -b "$branch" "$wt_path"
      fi

      echo ""
      echo "Worktree ready at: $WORKTREE_DIR/$branch"
      echo "  cd $wt_path"
    }

    cmd_ls() {
      ensure_git_repo
      git worktree list
    }

    cmd_rm() {
      local branch="''${1:-}"
      if [ -z "$branch" ]; then
        echo "Usage: wt rm <branch>" >&2
        exit 1
      fi

      ensure_git_repo
      local root
      root="$(get_root)"
      local wt_path="$root/$WORKTREE_DIR/$branch"

      if [ ! -d "$wt_path" ]; then
        echo "Error: No worktree at $WORKTREE_DIR/$branch" >&2
        exit 1
      fi

      # Check for uncommitted/untracked files
      local dirty_files
      dirty_files="$(git -C "$wt_path" status --porcelain 2>/dev/null || true)"

      local force_remove=false
      if [ -n "$dirty_files" ]; then
        echo "Worktree has uncommitted/untracked files:"
        echo "$dirty_files"
        echo ""
        read -r -p "Force remove worktree? [y/N] " answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
          force_remove=true
        else
          echo "Aborted."
          exit 0
        fi
      fi

      # Remove the worktree
      if [ "$force_remove" = true ]; then
        git worktree remove --force "$wt_path"
      else
        git worktree remove "$wt_path"
      fi
      echo "Removed worktree at $WORKTREE_DIR/$branch"

      # Check if branch exists before asking about it
      if ! git show-ref --verify --quiet "refs/heads/$branch"; then
        echo "Branch '$branch' does not exist (may have been removed already)."
        return
      fi

      # Ask about merging
      local merged=false
      read -r -p "Merge branch '$branch' into current branch? [y/N] " answer
      if [[ "$answer" =~ ^[Yy]$ ]]; then
        if git merge "$branch"; then
          merged=true
          echo "Merged '$branch' into $(git branch --show-current)"
        else
          echo "Merge failed — resolve conflicts manually." >&2
          return
        fi
      fi

      # Ask about deleting the branch
      read -r -p "Delete branch '$branch'? [Y/n] " answer
      if [[ "''${answer:-Y}" =~ ^[Nn]$ ]]; then
        echo "Keeping branch '$branch'."
        return
      fi

      # Try normal delete first
      if git branch -d "$branch" 2>/dev/null; then
        echo "Deleted branch '$branch'."
      else
        # Branch not fully merged
        if [ "$merged" = false ]; then
          echo "Branch '$branch' is not fully merged."
          read -r -p "Force delete branch? [y/N] " answer
          if [[ "$answer" =~ ^[Yy]$ ]]; then
            git branch -D "$branch"
            echo "Force deleted branch '$branch'."
          else
            echo "Keeping branch '$branch'."
          fi
        fi
      fi
    }

    # Main dispatch
    command="''${1:-help}"
    shift || true

    case "$command" in
      init) cmd_init "$@" ;;
      add)  cmd_add "$@" ;;
      ls)   cmd_ls "$@" ;;
      rm)   cmd_rm "$@" ;;
      help) usage ;;
      *)
        echo "Unknown command: $command" >&2
        usage >&2
        exit 1
        ;;
    esac
  '';
}
