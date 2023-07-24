let
  cmp = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMkZLn/cpSwMC3sgYGQJP7vCykLBN1emYuYv9L8N4izp cmp@cp-mba.local";
in
{
  "vault.age".publicKeys = [ cmp ];
}
