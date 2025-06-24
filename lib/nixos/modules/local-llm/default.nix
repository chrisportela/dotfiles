{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.chrisportela.local-llm;
in
with lib;
{
  options.chrisportela.local-llm = {
    enable = lib.mkEnableOption "Local Large-Language-Model config";
  };

  config = mkIf cfg.enable {
    allowedUnfree = [
      "cuda_cudart"
      "cuda-merged"
      "cuda_cuobjdump"
      "cuda_gdb"
      "cuda_nvcc"
      "cuda_nvdisasm"
      "cuda_nvprune"
      "cuda_cccl"
      "cuda_cupti"
      "cuda_cuxxfilt"
      "cuda_nvml_dev"
      "cuda_nvrtc"
      "cuda_nvtx"
      "cuda_profiler_api"
      "cuda_sanitizer_api"
      "libcublas"
      "libcufft"
      "libcurand"
      "libcusolver"
      "libnvjitlink"
      "libcusparse"
      "libnpp"
    ];

    nix.config = {
      cudaSupport = true;
      cudaCapabilities = [
        "8.6"
        "10.0"
        "12.0"
      ];
      # cudaForwardCompat = false;
    };

    nixpkgs.overlays = [
      (final: prev: {
        python3 = prev.python3.withPackages (
          ps: with ps; [ huggingface-hub ] ++ huggingface-hub.optional-dependencies.hf_transfer
        );
      })
    ];

    environment.systemPackages = [ python3-hf ];

    services.ollama = {
      enable = true;
      acceleration = "cuda";
      host = "127.0.0.1";
      port = 11434;
      environmentVariables = {
        OLLAMA_ORIGINS = "https://ollama.ada.i.cafecito.cloud";
        OLLAMA_KEEP_ALIVE = "48h";
        OLLAMA_NUM_PARALLEL = "1";
        OLLAMA_MAX_LOADED_MODELS = "3";
        OLLAMA_MAX_QUEUE = "512";
      };
    };

    # Ensure going to sleep does not kill ollama connection to GPU
    hardware.nvidia.powerManagement.enable = true;

    # Open Web UI
    virtualisation.oci-containers.containers = {
      kokoro = {
        autoStart = true;
        image = "ghcr.io/remsky/kokoro-fastapi-gpu:v0.2.4";
        ports = [ "127.0.0.1:8880:8880" ];
        extraOptions = [ "--device=nvidia.com/gpu=all" ];
      };
    };

    services.nginx.virtualHosts = {
      "ollama.ada.i.cafecito.cloud" = {
        forceSSL = true;
        enableACME = true;

        locations."/" = {
          proxyPass = "http://127.0.0.1:11434";
          #recommendedProxySettings = true;
          extraConfig = ''
            proxy_set_header Host localhost:11434;
          '';
        };

        extraConfig = ''
          access_log /var/log/nginx/ollama-cafeito_cloud.access.log;
          error_log /var/log/nginx/ollama-cafeito_cloud.error.log;
        '';
      };
    };
  };
}
