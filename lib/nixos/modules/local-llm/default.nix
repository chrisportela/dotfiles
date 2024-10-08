{ config, lib, pkgs, ... }:
let
  cfg = config.chrisportela.local-llm;
in
with lib; {
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

    services.ollama = {
      enable = true;
      acceleration = "cuda";
      listenAddress = "127.0.0.1:11434";
      environmentVariables = {
        OLLAMA_ORIGINS = "https://ollama.ada.i.cafecito.cloud";
        OLLAMA_KEEP_ALIVE = "12h";
      };
    };

    systemd.services.ollama-reload =
      let
        script = (pkgs.writeShellScriptBin "reload-ollama" ''
          systemctl stop ollama
          echo "Ollama service stopped"

          echo "Reloading Nvidia kernel modules"
          ${pkgs.kmod}/bin/rmmod nvidia_uvm && ${pkgs.kmod}/bin/modprobe nvidia_uvm

          echo "Starting Ollama service..."
          systemctl start ollama
        '');
      in
      {
        enable = false;
        description = "Reloads NVidia kernel modules and restarts ollama so it can use GPU after suspend.";
        after = [ "suspend.target" ];
        wantedBy = [ "suspend.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${script}/bin/reload-ollama";
        };
      };

    # Open Web UI
    virtualisation.oci-containers.containers.open-webui = {
      autoStart = true;
      image = "ghcr.io/open-webui/open-webui";
      # TODO figure out how to create the data directory declaratively
      volumes = [ "${config.users.users.cmp.home}/open-webui:/app/backend/data" ];
      extraOptions = [ "--network=host" "--add-host=host.containers.internal:host-gateway" ];
      environment = {
        OLLAMA_API_BASE_URL = "http://127.0.0.1:11434/api";
        OLLAMA_BASE_URL = "http://127.0.0.1:11434";
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
        };

        extraConfig = ''
          access_log /var/log/nginx/chat-cafeito_cloud.access.log;
          error_log /var/log/nginx/chat-cafeito_cloud.error.log;
        '';
      };
    };
  };
}
