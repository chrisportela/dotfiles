let
  mbaHomeSE = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBLKmP5UUboT3SkiyHzY81/7UGG0SrVcSWxywkD8lpxYznrFz2uWT6zGfiQNj8FrLSwrh/AthIZJfe0LvbKEtTq8= home@secretive.cp-mba.local";
  nixKeyWindows = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII5kFjpHHMhPxXAp54egnvuGVidd0g83jrw9AzD3AB5N cp@cp-win1";
in
{
  cmp = [ mbaHomeSE nixKeyWindows ];
  builder = [ mbaHomeSE nixKeyWindows ];
}
