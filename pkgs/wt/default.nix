{
  lib,
  rustPlatform,
  installShellFiles,
  git,
  tmux,
}:

rustPlatform.buildRustPackage {
  pname = "wt";
  version = "0.2.0";

  src = lib.cleanSource ./.;
  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [ installShellFiles ];

  # checkPhase runs the hermetic test suite: a real git repo in a tempdir and
  # a private tmux server (WT_TMUX_SOCKET), no network. direnv/claude are
  # exercised through logging shims, so they are not needed here.
  nativeCheckInputs = [
    git
    tmux
  ];

  postInstall = ''
    installShellCompletion --cmd wt \
      --bash completions/wt.bash \
      --zsh  completions/_wt \
      --fish completions/wt.fish
    install -Dm644 completions/wt.nu $out/share/nushell/vendor/autoload/wt.nu
  '';

  meta = {
    description = "Git worktree manager: .worktrees/ layout, direnv setup, tmux automation";
    platforms = lib.platforms.unix;
    mainProgram = "wt";
    # Runtime deps (git, tmux, direnv, claude) are deliberately resolved from
    # the user's PATH, not wrapped into the closure: wt orchestrates the
    # user's own environment.
  };
}
