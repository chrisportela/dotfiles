{ pkgs, lib, direnv, }:
let direnvBin = "${direnv}/bin/direnv";
in (pkgs.writeShellScriptBin "setup-envrc" ''
  set -eu

  # Check if we're in a git repository
  if [ ! -d .git ]; then
    echo "Error: Not in a git repository" >&2
    exit 1
  fi

  # Determine flake reference
  if [ -d "$HOME/src/dotfiles" ]; then
    FLAKE_REF="$HOME/src/dotfiles#dev"
  else
    FLAKE_REF="github:chrisportela/dotfiles#dev"
  fi

  # Create or update .envrc
  ENVRC_CONTENT="use flake $FLAKE_REF"
  if [ -f .envrc ]; then
    CURRENT_CONTENT=$(cat .envrc)
    if [ "$CURRENT_CONTENT" != "$ENVRC_CONTENT" ]; then
      echo "$ENVRC_CONTENT" > .envrc
      echo "Updated .envrc"
    else
      echo ".envrc already exists with correct content"
    fi
  else
    echo "$ENVRC_CONTENT" > .envrc
    echo "Created .envrc"
  fi

  # Ensure .git/info/exclude exists
  mkdir -p .git/info
  touch .git/info/exclude

  # Add .envrc to .git/info/exclude if not already present
  if ! grep -q "^\.envrc$" .git/info/exclude 2>/dev/null; then
    echo ".envrc" >> .git/info/exclude
    echo "Added .envrc to .git/info/exclude"
  fi

  # Add .direnv to .git/info/exclude if not already present
  if ! grep -q "^\.direnv$" .git/info/exclude 2>/dev/null; then
    echo ".direnv" >> .git/info/exclude
    echo "Added .direnv to .git/info/exclude"
  fi

  # Approve the .envrc with direnv
  if command -v ${direnvBin} >/dev/null 2>&1; then
    ${direnvBin} allow
    echo "Approved .envrc with direnv"
  else
    echo "Warning: direnv not found in PATH, skipping approval" >&2
    echo "Run 'direnv allow' manually to approve the .envrc file"
  fi
'') // {
  meta = {
    description = "Setup and approve .envrc file in git repositories";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ "chrisportela" ];
    platforms = lib.platforms.unix;
  };
}
