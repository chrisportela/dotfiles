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

    environment.systemPackages = with pkgs; let
      python3-hf = python3.withPackages(ps: with ps; [ huggingface-hub ] ++ huggingface-hub.optional-dependencies.hf_transfer);
    in
    [
      python3-hf
    ];

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
      open-webui = {
        autoStart = true;
        image = "ghcr.io/open-webui/open-webui:v0.6.5";
        # TODO figure out how to create the data directory declaratively
        volumes = [ "${config.users.users.cmp.home}/open-webui:/app/backend/data" ];
        extraOptions = [
          "--network=host"
          "--add-host=host.containers.internal:host-gateway"
        ];
        environment = {
          OLLAMA_API_BASE_URL = "http://127.0.0.1:11434/api";
          OLLAMA_BASE_URL = "http://127.0.0.1:11434";
        };
      };
      kokoro = {
        autoStart = true;
        image = "ghcr.io/remsky/kokoro-fastapi-gpu:v0.2.2";
        ports = [ "127.0.0.1:8880:8880" ];
        extraOptions = [ "--device=nvidia.com/gpu=all" ];
      };
    };

    services.searx = {
      enable = true;
      redisCreateLocally = false;
      settings = {
        server.port = 8081;
        server.bind_address = "127.0.0.1";
        server.secret_key = "@SEARX_SECRET_KEY@";
        server.limiter = false;

        search = {
          safe_search = 0;
          formats = [
            "html"
            "json"
          ];
        };

        # engines = lib.singleton {
        #   name = "wolframalpha";
        #   shortcut = "wa";
        #   api_key = "@WOLFRAM_API_KEY@";
        #   engine = "wolframalpha_api";
        # };
      };
      uwsgiConfig = {
        http = ":8081";
      };
      limiterSettings = {
        # real_ip = {
        #   x_for = 1;
        #   ipv4_prefix = 32;
        #   ipv6_prefix = 56;
        # };
        # botdetection.ip_lists.block_ip = [
        #   # "93.184.216.34" # example.org
        # ];
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

      "chat.ada.i.cafecito.cloud" = {
        forceSSL = true;
        enableACME = true;

        locations."/" = {
          proxyPass = "http://127.0.0.1:8080";
          recommendedProxySettings = true;
          proxyWebsockets = true;
        };

        extraConfig = ''
          client_max_body_size 100M;
          access_log /var/log/nginx/chat-cafeito_cloud.access.log;
          error_log /var/log/nginx/chat-cafeito_cloud.error.log;
        '';
      };
    };
  };
}
