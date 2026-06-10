{
  lib,
  fetchurl,
  stdenv,
}:

let
  inherit (stdenv) hostPlatform;
  version = "0.9.31";
  sources = {
    x86_64-linux = fetchurl {
      url = "https://github.com/AlexsJones/llmfit/releases/download/v${version}/llmfit-v${version}-x86_64-unknown-linux-musl.tar.gz";
      hash = "sha256-b67nsjWOH12tHfVl7FGONW94ef6QvmynFbGsRQaswvw=";
    };
    aarch64-linux = fetchurl {
      url = "https://github.com/AlexsJones/llmfit/releases/download/v${version}/llmfit-v${version}-aarch64-unknown-linux-musl.tar.gz";
      hash = "sha256-AAlsNXqXShjmJgGjh5MYw92M+9ZtkwNsVu/0YbC8190=";
    };
    x86_64-darwin = fetchurl {
      url = "https://github.com/AlexsJones/llmfit/releases/download/v${version}/llmfit-v${version}-x86_64-apple-darwin.tar.gz";
      hash = "sha256-u1L+bjRMsmXg3iDiQ3LB2/2KHHUCCg2MY432FCYxQ+w=";
    };
    aarch64-darwin = fetchurl {
      url = "https://github.com/AlexsJones/llmfit/releases/download/v${version}/llmfit-v${version}-aarch64-apple-darwin.tar.gz";
      hash = "sha256-NuJ9gD+3QHgt1qZMdRHgn5OGT+HMXs+Ya534ULsy3Wk=";
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
