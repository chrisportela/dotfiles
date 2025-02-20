#!/bin/bash

notify() {
    local cmd="$*"
    local start_time=$(date '+%s%N')

    # Check for topic file and exit silently if it doesn't exist or is empty
    local topic=$(cat "$HOME"/.config/ntfy/scripts-topic 2> /dev/null | head -n1)

    if [[ -z "$topic" ]]; then
        echo "Error: no topic at '~/.config/ntfy/scripts-topic'"
        return "1"
    fi

    # Run the command
    eval "$cmd"
    local exit_code=$?

    # Calculate the time taken
    local end_time=$(date '+%s%N')
    local duration=$(( (end_time - start_time) / 1000000 )) # duration in ms

    # Only send notification if duration exceeds 5000 ms (5 seconds)
    if (( duration >= 5000 )); then
      # Convert duration from milliseconds to hours, minutes, and seconds
      local duration_sec=$(( duration / 1000 ))
      local hours=$(( duration_sec / 3600 ))
      local minutes=$(( (duration_sec % 3600) / 60 ))
      local seconds=$(( duration_sec % 60 ))

      # Format as "XhYmZs" or similar
      local formatted_duration
      if (( hours > 0 )); then
          formatted_duration="${hours}h${minutes}m${seconds}s"
      elif (( minutes > 0 )); then
          formatted_duration="${minutes}m${seconds}s"
      else
          formatted_duration="${seconds}s"
      fi

      # Determine the tag based on exit code
      local tag="white_check_mark"
      local priority="low"
      if (( exit_code != 0 )); then
          tag="warning"
          priority="high"
      fi

      # Construct the notification message
      local message=$(printf "Exit: $exit_code | Time: ${formatted_duration}\n\`${cmd}\`")

      # Send notification via ntfy CLI or curl
      if command -v ntfy &> /dev/null; then
          ntfy send --md -p $priority -T $tag --title "Finished command on ${HOSTNAME:-$HOST}" "$topic" "$message" &> /dev/null
      else
          curl -d "$message" https://ntfy.cafecito.cloud/"$topic" &> /dev/null
      fi
    fi

    return "$exit_code"
}

notify_finished() {
    local cmd="${1:-${BASH_COMMAND:-$(fc -ln -1)}}"
    local start_time=$2
    local duration=$((SECONDS - start_time))
    local exit_code=$3

    # Only proceed if duration exceeds 5 seconds
    if (( duration < 5 )); then
        return "$exit_code"
    fi

    # Check for topic file and exit silently if it doesn't exist or is empty
    local topic=$(cat "$HOME"/.config/ntfy/scripts-topic 2> /dev/null | head -n1)

    if [[ -z "$topic" ]]; then
        echo "Warning: no topic at '~/.config/ntfy/scripts-topic'"
        return "$exit_code"
    fi

    # Determine tag and priority based on exit code
    local tag="success"
    local priority="low"
    if (( exit_code != 0 )); then
        tag="error"
        priority="high"
    fi

    # Construct the notification message
    local message=$(printf "Exit: $exit_code | Time: ${duration}s\n\`${cmd}\`")

    # Send notification via ntfy CLI or curl
    if command -v ntfy &> /dev/null; then
        ntfy send -p "$priority" --md --title "Finished command on ${HOSTNAME:-$HOST}" $topic "$message" &> /dev/null
    else
        curl -d "$message" https://ntfy.cafecito.cloud/"$topic" &> /dev/null
    fi

    return $exit_code
}

enable_ntfy_trap() {
    if [[ -n "$ZSH_VERSION" ]]; then
        autoload -Uz add-zsh-hook
        add-zsh-hook preexec __ntfy_preexec
        add-zsh-hook precmd __ntfy_precmd
    elif [[ -n "$BASH_VERSION" ]]; then
        trap '__ntfy_preexec "$BASH_COMMAND"' DEBUG
        PROMPT_COMMAND='__ntfy_precmd'
    fi
}

__ntfy_preexec() {
    __ntfy_start_time=$SECONDS
    __ntfy_last_command="$1"
}

__ntfy_precmd() {
    local exit_code=$?
    if [[ -n "$__ntfy_start_time" ]]; then
        notify_finished "$__ntfy_last_command" "$__ntfy_start_time" "$exit_code"
        unset __ntfy_start_time
        unset __ntfy_last_command
    fi
}

# change into directory of a file
cdd() {
  cd $(dirname ${@:})
}

# Create a new directory and enter it
mkd() {
	mkdir -p "$@"
	cd "$@" || exit
}

# Make a temporary directory and enter it
tmpd() {
	local dir
	if [ $# -eq 0 ]; then
		dir=$(mktemp -d)
	else
		dir=$(mktemp -d -t "${1}.XXXXXXXXXX")
	fi
	cd "$dir" || exit
}

# Use Git’s colored diff when available
if hash git &>/dev/null ; then
	diff() {
		git diff --no-index --color-words "$@"
	}
fi

# Create a data URL from a file
dataurl() {
	local mimeType
	mimeType=$(file -b --mime-type "$1")
	if [[ $mimeType == text/* ]]; then
		mimeType="${mimeType};charset=utf-8"
	fi
	echo "data:${mimeType};base64,$(openssl base64 -in "$1" | tr -d '\n')"
}

# `o` with no arguments opens the current directory, otherwise opens the given
# location
o() {
	if [ $# -eq 0 ]; then
		open .	> /dev/null 2>&1
	else
		open "$@" > /dev/null 2>&1
	fi
}

# Call from a local repo to open the repository on github/bitbucket in browser
# Modified version of https://github.com/zeke/ghwd
repo() {
	# Figure out github repo base URL
	local base_url
	base_url=$(git config --get remote.origin.url)
	base_url=${base_url%\.git} # remove .git from end of string

	# Fix git@github.com: URLs
	base_url=${base_url//git@github\.com:/https:\/\/github\.com\/}

	# Fix git://github.com URLS
	base_url=${base_url//git:\/\/github\.com/https:\/\/github\.com\/}

	# Fix git@bitbucket.org: URLs
	base_url=${base_url//git@bitbucket.org:/https:\/\/bitbucket\.org\/}

	# Fix git@gitlab.com: URLs
	base_url=${base_url//git@gitlab\.com:/https:\/\/gitlab\.com\/}

	# Validate that this folder is a git folder
	if ! git branch 2>/dev/null 1>&2 ; then
		echo "Not a git repo!"
		exit $?
	fi

	# Find current directory relative to .git parent
	full_path=$(pwd)
	git_base_path=$(cd "./$(git rev-parse --show-cdup)" || exit 1; pwd)
	relative_path=${full_path#$git_base_path} # remove leading git_base_path from working directory

	# If filename argument is present, append it
	if [ "$1" ]; then
		relative_path="$relative_path/$1"
	fi

	# Figure out current git branch
	# git_where=$(command git symbolic-ref -q HEAD || command git name-rev --name-only --no-undefined --always HEAD) 2>/dev/null
	git_where=$(command git name-rev --name-only --no-undefined --always HEAD) 2>/dev/null

	# Remove cruft from branchname
	branch=${git_where#refs\/heads\/}

	[[ $base_url == *bitbucket* ]] && tree="src" || tree="tree"
	url="$base_url/$tree/$branch$relative_path"


	echo "Calling $(type open) for $url"

	open "$url" &> /dev/null || (echo "Using $(type open) to open URL failed." && exit 1);
}

# Get colors in manual pages
man() {
	env \
		LESS_TERMCAP_mb="$(printf '\e[1;31m')" \
		LESS_TERMCAP_md="$(printf '\e[1;31m')" \
		LESS_TERMCAP_me="$(printf '\e[0m')" \
		LESS_TERMCAP_se="$(printf '\e[0m')" \
		LESS_TERMCAP_so="$(printf '\e[1;44;33m')" \
		LESS_TERMCAP_ue="$(printf '\e[0m')" \
		LESS_TERMCAP_us="$(printf '\e[1;32m')" \
		man "$@"
}


gitsetoriginnopush() {
	git remote set-url --push origin no_push
}


gco () {
    if [[ ! -z "$1" ]]; then
        git checkout $@
        return
    fi

    git checkout $(git branch --color=always --sort=-committerdate --format='%(refname:short)' | fzf)
}

switch-darwin () {
    darwin-rebuild switch --flake $HOME/src/dotfiles
}

switch-nix () {
    sudo nixos-rebuild switch --flake $HOME/src/dotfiles
}

switch-home () {
    local dotfiles=${DOTFILES_DIR:="$HOME/src/dotfiles"}

    home-manager switch -b backup --flake $dotfiles
}

which() {
  local prog=$1
  local which_path=$(command which "$prog")
  if [ -L "$which_path" ]; then
    echo "$which_path -> $(readlink -f "$which_path")"
  else
    echo "$which_path"
  fi
}
