# Host-specific config for lux: the darwin CI builder.
# Runs the Forgejo Actions runner (labels: darwin/nix-darwin/lux-darwin)
# and pushes everything it builds to the niks3 cache.
{ config, ... }:
{
  chrisportela.forgejo-runner = {
    enable = true;
    name = "lux";
    labels = [
      "lux-darwin:host"
      "darwin:host"
      "nix-darwin:host"
    ];
    tokenFile = config.age.secrets.lux-forgejo-runner-token.path;
  };

  chrisportela.nix-cache-push = {
    enable = true;
    tokenFile = config.age.secrets.lux-niks3-api-token.path;
  };

  age.secrets.lux-forgejo-runner-token = {
    file = ../../secrets/lux-forgejo-runner-token.age;
    # The runner daemon (and its registration step) runs as cmp.
    owner = "cmp";
    mode = "0400";
  };

  age.secrets.lux-niks3-api-token = {
    # Read by the post-build hook inside the root nix-daemon; defaults
    # (root:0400) are correct.
    file = ../../secrets/lux-niks3-api-token.age;
  };
}
