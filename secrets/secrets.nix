let
  sshKeys = import ../lib/sshKeys.nix;
in
{
  "example.age".publicKeys = sshKeys.secrets ++ [ ];
}
