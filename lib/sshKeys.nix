let
  mbaHomeSE = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBHN+RyedBKQ/UStTC2anytbwhHI10PPDfpfJLpTtTvlPRw4mhw95TaQlUfOmT3kTB3YmNzbCbssFW5zR9ZbKY3s= home@secretive.lux.local";
  mbaGithubSE = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBOnchsLQT478nuW7DvquEv4dG3CYovttcGEB1pZagkM6Jz5lvJUhIfealse/6V4GAKu4OtN1HG6WhaqgGgg8DEY= github@secretive.lux.local";
  iphoneSE = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBK4wf5IKlAiOd4CDjFsRPZvWTq2QaETTE2Ix3onN18q+6RCHAjq9wELHd7P140t2TrK+k8hhd6sryoRmYl+Z5kQ= ShellFish-SE@iPhone-23072024";
  iphoneEd25519 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAzxvjRupAABCMRfZURSWZZcWRncglE+61vQp7t8uQr ShellFish@iPhone-23072024";
  windowsDesktop = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII5kFjpHHMhPxXAp54egnvuGVidd0g83jrw9AzD3AB5N cp@cp-win1";
  nixDesktop = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILsqpaOSjCbxoTry3oYRHElBMbnFvZVVa5sxjbTZO/lX cmp@ada";
in
{
  keys = {
    mba = mbaHomeSE;
    iphone = iphoneSE;
    desktop-win = windowsDesktop;
    desktop-nix = nixDesktop;
  };

  # Default Keys for users
  users = {
    cmp = [ mbaHomeSE windowsDesktop ];
    builder = [ mbaHomeSE windowsDesktop ];
  };

  default = [
    mbaGithubSE
  ];
}
