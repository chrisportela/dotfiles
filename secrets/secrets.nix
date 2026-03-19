let
  sshKeys = import ../lib/ssh-keys.nix;
  ada = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILsqpaOSjCbxoTry3oYRHElBMbnFvZVVa5sxjbTZO/lX cmp@ada";
in
{
  "example.age".publicKeys = sshKeys.secrets ++ [ ];
  "ada-samba-passwords.age".publicKeys = sshKeys.secrets ++ [ ada ];
}
