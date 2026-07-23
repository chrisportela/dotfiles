{
  lib,
  fetchurl,
  stdenv,
}:

let
  inherit (stdenv) hostPlatform;
  version = "1.1.6";
  sources = {
    x86_64-linux = fetchurl {
      url = "https://github.com/AlexsJones/llmfit/releases/download/v${version}/llmfit-v${version}-x86_64-unknown-linux-musl.tar.gz";
      hash = "sha256-HgkjKhKEVVlqLTSKtYk3QdBLlKptkk8SU0YtwTME98Y=";
    };
    aarch64-linux = fetchurl {
      url = "https://github.com/AlexsJones/llmfit/releases/download/v${version}/llmfit-v${version}-aarch64-unknown-linux-musl.tar.gz";
      hash = "sha256-v1kH10hiH8CEF0akeKVVoNrQ1OLA82LeIvm5eIxm0Kc=";
    };
    x86_64-darwin = fetchurl {
      url = "https://github.com/AlexsJones/llmfit/releases/download/v${version}/llmfit-v${version}-x86_64-apple-darwin.tar.gz";
      hash = "sha256-CWcg5rYR0/TO1ht1+M6z6uPda0aWXyvAesYjf99IDus=";
    };
    aarch64-darwin = fetchurl {
      url = "https://github.com/AlexsJones/llmfit/releases/download/v${version}/llmfit-v${version}-aarch64-apple-darwin.tar.gz";
      hash = "sha256-jD46I533FyIdqRAs22LgJRnU+Vr1jRpFw4DGqpF8P68=";
    };
  };
in
stdenv.mkDerivation {
  pname = "llmfit";
  inherit version;

  src = sources.${hostPlatform.system} or (throw "llmfit: unsupported system ${hostPlatform.system}");

  # Tarball contains a single top-level directory (llmfit-v${version}-<target>/);
  # stdenv auto-detects sourceRoot, so we deliberately do NOT set it.

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 llmfit -t $out/bin
    install -Dm644 LICENSE -t $out/share/licenses/llmfit
    install -Dm644 README.md -t $out/share/doc/llmfit
    runHook postInstall
  '';

  passthru = {
    inherit sources;
    updateScript = ./update.sh;
  };

  meta = {
    description = "Right-sizes LLM models to your system's RAM, CPU, and GPU";
    homepage = "https://github.com/AlexsJones/llmfit";
    license = lib.licenses.mit;
    platforms = builtins.attrNames sources;
    mainProgram = "llmfit";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
