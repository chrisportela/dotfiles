let
  inherit (import ../lib/sshKeys.nix) cmp;
in
{
  "example.age".publicKeys = [ cmp ];
}
