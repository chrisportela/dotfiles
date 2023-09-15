let
  mbaHomeSE = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBHN+RyedBKQ/UStTC2anytbwhHI10PPDfpfJLpTtTvlPRw4mhw95TaQlUfOmT3kTB3YmNzbCbssFW5zR9ZbKY3s= home@secretive.lux.local";
  nixKeyWindows = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII5kFjpHHMhPxXAp54egnvuGVidd0g83jrw9AzD3AB5N cp@cp-win1";
in
{
  cmp = [ mbaHomeSE nixKeyWindows ];
  builder = [ mbaHomeSE nixKeyWindows ];
}
