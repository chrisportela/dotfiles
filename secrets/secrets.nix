let
  sshKeys = import ../lib/ssh-keys.nix;
  # age only supports ssh-ed25519 / ssh-rsa recipients — the Secretive
  # (ECDSA) keys cannot decrypt agenix secrets, so admin access goes
  # through the ed25519 user keys.
  admins = [
    sshKeys.keys.desktop-nix
    sshKeys.keys.desktop-win
  ];
in
{
  "example.age".publicKeys = sshKeys.secrets ++ [ ];

  # Shared secret for lux's pre-registered Forgejo Actions runner
  # (modules/darwin/forgejo-runner). Generate with `openssl rand -hex 20`,
  # register the same value server-side on liara:
  #   forgejo-cli actions register --name lux --secret <secret>
  "lux-forgejo-runner-secret.age".publicKeys = [ sshKeys.hostKeys.lux ] ++ admins;

  # niks3 API token for lux's post-build cache push
  # (modules/darwin/nix-cache-push). Minted on liara (infra repo).
  "lux-niks3-api-token.age".publicKeys = [ sshKeys.hostKeys.lux ] ++ admins;
}
