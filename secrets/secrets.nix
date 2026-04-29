let
  sshKeys = import ../lib/ssh-keys.nix;
in
{
  "example.age".publicKeys = sshKeys.secrets ++ [ ];
}
