{
  upstreamOpencode,
}:

let
  version = "1.3.13";
in
upstreamOpencode.overrideAttrs (
  finalAttrs: prev: {
    inherit version;

    src = prev.src.override {
      tag = "v${version}";
      hash = "sha256-P6Md0WzHK2/oAZ6VbpYnabVJyVcqwuYizoOqbxaf+lU=";
    };

    node_modules = prev.node_modules.overrideAttrs {
      inherit (finalAttrs) version src;
      outputHash = "sha256-fWc9xVn6HbNxnJ9S8Q+hdlYQYkdGk+4RWWbYaB+L09Q=";
    };

    passthru = prev.passthru // {
      updateScript = ./update.sh;
    };
  }
)
