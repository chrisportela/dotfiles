# Host-specific config for lux: the darwin CI builder.
# Runs the Forgejo Actions runner (labels: darwin/nix-darwin/lux-darwin)
# and pushes everything it builds to the niks3 cache.
{ config, ... }:
{
  chrisportela.forgejo-runner = {
    enable = true;
    # Placeholder — replace with the real UUID after pre-registering:
    # generate `openssl rand -hex 20`, run
    # `forgejo-cli actions register --name lux --secret <secret>` on liara
    # (prints the UUID), and store the secret via
    # `agenix -e lux-forgejo-runner-secret.age`.
    uuid = "00000000-0000-0000-0000-000000000000";
    labels = [
      "lux-darwin:host"
      "darwin:host"
      "nix-darwin:host"
    ];
    secretFile = config.age.secrets.lux-forgejo-runner-secret.path;
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
