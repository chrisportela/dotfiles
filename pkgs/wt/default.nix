{
  writeShellApplication,
  git,
  coreutils,
  installShellFiles,
  lib,
}:

let
  wt = writeShellApplication {
    name = "wt";

    runtimeInputs = [
      git
      coreutils
    ];

    meta = with lib; {
      platforms = platforms.unix ++ platforms.darwin;
    };

    text = ''
      WORKTREE_DIR=".worktrees"

      usage() {
        echo "Usage: wt <command> [args]"
        echo ""
        echo "Commands:"
        echo "  init          Setup .worktrees/ and add to .git/info/exclude"
        echo "  add [--no-direnv] <branch>  Create a worktree with a new or existing branch"
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

      upstream_gone() {
        # $1 = branch name
        # Returns 0 iff the branch has an upstream tracking ref that is now gone.
        # This is the typical state after a GitHub squash-/rebase-merge where
        # the PR branch was auto-deleted on the remote.
        local track
        track=$(git for-each-ref --format='%(upstream:track)' "refs/heads/$1")
        [[ "$track" == *"[gone]"* ]]
      }

      wt_find_envrcs() {
        # $1 = path. Prints relative paths of all .envrc files, sorted.
        local p="$1"
        find "$p" -name .envrc -not -path '*/.git/*' 2>/dev/null | sort | while IFS= read -r f; do
          printf '%s\n' "''${f#"$p"/}"
        done
      }

      wt_allow_envrcs() {
        # $1 = worktree path. Calls `direnv allow` on each .envrc found.
        # Prints "  allowed: <relative>" per file. Caller is responsible for
        # the `command -v direnv` availability check.
        local p="$1" rel
        while IFS= read -r rel; do
          [ -z "$rel" ] && continue
          direnv allow "$p/$rel"
          echo "  allowed: $rel"
        done < <(wt_find_envrcs "$p")
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
        local branch=""
        local skip_direnv=false
        while [ $# -gt 0 ]; do
          case "$1" in
            --no-direnv) skip_direnv=true; shift ;;
            -*) echo "Unknown flag: $1" >&2; exit 1 ;;
            *)
              if [ -z "$branch" ]; then
                branch="$1"; shift
              else
                echo "Unexpected argument: $1" >&2; exit 1
              fi
              ;;
          esac
        done

        if [ -z "$branch" ]; then
          echo "Usage: wt add [--no-direnv] <branch>" >&2
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

        if [ "$skip_direnv" != true ] && command -v direnv >/dev/null 2>&1; then
          local envrc_list
          envrc_list=$(wt_find_envrcs "$wt_path")
          if [ -n "$envrc_list" ]; then
            local n
            n=$(printf '%s\n' "$envrc_list" | wc -l)
            echo ""
            echo "Approving $n .envrc file(s) with direnv:"
            wt_allow_envrcs "$wt_path"
          fi
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
            if upstream_gone "$branch"; then
              echo "Branch '$branch' is not fully merged locally, but its upstream"
              echo "tracking branch is gone. This usually means it was squash- or"
              echo "rebase-merged on the remote and then deleted (common on GitHub"
              echo "PR merge). Recommending force delete."
              read -r -p "Force delete branch? [Y/n] " answer
              if [[ "''${answer:-Y}" =~ ^[Nn]$ ]]; then
                echo "Keeping branch '$branch'."
              else
                git branch -D "$branch"
                echo "Force deleted branch '$branch'."
              fi
            else
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
  };
in
wt.overrideAttrs (old: {
  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ installShellFiles ];
  buildCommand = (old.buildCommand or "") + ''
    installShellCompletion --cmd wt \
      --bash ${./completions/wt.bash} \
      --zsh  ${./completions/_wt} \
      --fish ${./completions/wt.fish}
    install -Dm644 ${./completions/wt.nu} \
      $out/share/nushell/vendor/autoload/wt.nu
  '';
})
