# Host-specific config for lux: the darwin CI builder.
# Runs the Forgejo Actions runner (labels: darwin/nix-darwin/lux-darwin)
# and pushes everything it builds to the niks3 cache.
{ config, ... }:
{
  chrisportela.forgejo-runner = {
    enable = true;
    uuid = "1df45530-8a2a-4a18-ae94-49936aa2a863";
    labels = [
      "lux-darwin:host"
      "darwin:host"
      "nix-darwin:host"
    ];
    secretFile = config.age.secrets.lux-forgejo-runner-secret.path;
    # git.cafecito.cloud is signed by the internal CA; nix-built git/curl
    # don't read the macOS Keychain, so it must be in the PEM bundle.
    extraCertificateFiles = [ ../../lib/cafecito-root-ca.crt ];
  };

  chrisportela.nix-cache-push = {
    enable = true;
    tokenFile = config.age.secrets.lux-niks3-api-token.path;
  };

  age.secrets.lux-forgejo-runner-secret = {
    file = ../../secrets/lux-forgejo-runner-secret.age;
    # The runner daemon (and its create-runner-file step) runs as cmp.
    owner = "cmp";
    mode = "0400";
  };

  age.secrets.lux-niks3-api-token = {
    # Read by the post-build hook inside the root nix-daemon; defaults
    # (root:0400) are correct.
    file = ../../secrets/lux-niks3-api-token.age;
  };
}
