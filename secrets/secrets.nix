let
  sshKeys = import ../lib/ssh-keys.nix;
  ada = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILsqpaOSjCbxoTry3oYRHElBMbnFvZVVa5sxjbTZO/lX cmp@ada";
  adaHost = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINzAkODt0f1rcTToP7ajlylJtj4IfmyLgCW8yE5ze+UT root@ada";
in
{
  "example.age".publicKeys = sshKeys.secrets ++ [ ];
  "ada-samba-passwords.age".publicKeys = sshKeys.secrets ++ [
    ada
    adaHost
  ];
}
