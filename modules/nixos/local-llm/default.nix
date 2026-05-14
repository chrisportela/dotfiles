{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.chrisportela.local-llm;
  vcfg = cfg.vllm;
  stateDir = "/var/lib/vllm";
  hfCacheDir = "${stateDir}/hf";
  compileCacheDir = "${stateDir}/cache";
in
with lib;
{
  options.chrisportela.local-llm = {
    enable = mkEnableOption "Local Large-Language-Model config";

    vllm = {
      enable = mkEnableOption "vLLM OpenAI-compatible inference server";

      model = mkOption {
        type = types.str;
        description = ''
          HuggingFace repo ID to serve. Downloaded on first start by the
          vllm-model-download.service into ${hfCacheDir}.
        '';
        example = "Qwen/Qwen2.5-Coder-14B-Instruct-AWQ";
      };

      toolCallParser = mkOption {
        type = types.str;
        description = ''
          vLLM tool-call parser matching the model family. Determines how
          streamed tool calls are extracted from the model's raw output.
          The set of valid names is whatever the running vLLM version
          registers — see `vllm/tool_parsers/__init__.py` in the pinned
          nixpkgs source. Common values: `hermes`, `llama3_json`, `mistral`,
          `pythonic`, `qwen3_coder`, `qwen3_xml`, `functiongemma`. vLLM
          validates this at startup and fails with the full list if it
          doesn't recognise the name.
        '';
        example = "qwen3_xml";
      };

      gpuMemoryUtilization = mkOption {
        type = types.float;
        default = 0.9;
        description = ''
          Fraction of GPU memory vLLM may allocate (0.0-1.0). Lower this if
          other GPU workloads run concurrently on the same device.
        '';
      };

      maxModelLen = mkOption {
        type = types.ints.positive;
        default = 8192;
        description = ''
          Maximum sequence length (context window) in tokens. vLLM pre-allocates
          KV-cache based on this — raising it costs VRAM.
        '';
      };

      maxNumSeqs = mkOption {
        type = types.ints.positive;
        default = 256;
        description = ''
          Maximum number of concurrent sequences in a single batch. vLLM
          pre-allocates KV-cache for `maxNumSeqs * maxModelLen` tokens, so on
          smaller GPUs you usually need to drop this from the upstream default
          (256) to fit a long context window in VRAM.
        '';
      };

      port = mkOption {
        type = types.port;
        default = 8000;
        description = "HTTP port for the OpenAI-compatible API (bound to 127.0.0.1).";
      };

      servedModelName = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Short alias clients use in the OpenAI API `model` field. If null,
          the full HuggingFace repo ID is used.
        '';
        example = "qwen3-coder";
      };

      extraFlags = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Additional flags appended to `vllm serve`.";
        example = [
          "--dtype"
          "auto"
          "--quantization"
          "awq_marlin"
        ];
      };

      vhost = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          If set, expose the vLLM API over HTTPS at this nginx virtualHost
          name with ACME. vLLM ships no auth — pair with oauth-proxy, basic
          auth, or restrict to a trusted network before exposing publicly.
        '';
        example = "vllm.ada.i.cafecito.cloud";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
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
        "libcusparse_lt"
        "libcufile"
        "cudnn"
        "libnpp"
      ];

      nixpkgs.config = {
        cudaSupport = true;
      };

      nixpkgs.overlays = [
        (final: prev: {
          python3-hf = prev.python3.withPackages (
            ps: with ps; [ huggingface-hub ] ++ (with huggingface-hub.optional-dependencies; (hf_xet ++ torch))
          );
        })
      ];

      environment.sessionVariables = {
        CUDA_PATH = "${pkgs.cudatoolkit}";
        LD_LIBRARY_PATH = [
          "${pkgs.linuxPackages.nvidia_x11}/lib"
          "${pkgs.cudaPackages.cuda_nvml_dev}/lib"
          "${pkgs.ncurses5}/lib"
        ];
      };

      services.xserver.videoDrivers = [ "nvidia" ];
      hardware.nvidia.open = true;
      hardware.nvidia-container-toolkit = {
        enable = true;
        mount-nvidia-executables = false;
      };

      programs.nix-ld.enable = true;

      environment.systemPackages = [
        pkgs.cudatoolkit
        pkgs.cudatoolkit.lib
        pkgs.cudaPackages.cuda_nvml_dev
        pkgs.python3-hf
      ];

      # Ensure going to sleep does not kill GPU state
      hardware.nvidia.powerManagement.enable = true;

      # Kokoro TTS — unrelated to LLM serving, kept here for convenience.
      virtualisation.oci-containers.containers = {
        kokoro = {
          autoStart = true;
          image = "ghcr.io/remsky/kokoro-fastapi-gpu:v0.2.4";
          ports = [ "127.0.0.1:8880:8880" ];
          extraOptions = [ "--device=nvidia.com/gpu=all" ];
        };
      };
    }

    (mkIf vcfg.enable {
      users.users.vllm = {
        isSystemUser = true;
        group = "vllm";
        home = stateDir;
        createHome = false;
      };
      users.groups.vllm = { };

      systemd.tmpfiles.rules = [
        "d ${stateDir}            0750 vllm vllm - -"
        "d ${hfCacheDir}          0750 vllm vllm - -"
        "d ${compileCacheDir}     0750 vllm vllm - -"
        "d ${compileCacheDir}/vllm   0750 vllm vllm - -"
        "d ${compileCacheDir}/torch  0750 vllm vllm - -"
        "d ${compileCacheDir}/triton 0750 vllm vllm - -"
      ];

      # One-shot prefetch. Runs before vllm.service so the model is on-disk
      # before the engine starts. Idempotent: hf checks local
      # cache hashes and only downloads missing shards.
      systemd.services.vllm-model-download = {
        description = "Download vLLM model (${vcfg.model}) from HuggingFace";
        wantedBy = [ "multi-user.target" ];
        before = [ "vllm.service" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];

        environment = {
          HF_HOME = hfCacheDir;
          HUGGINGFACE_HUB_CACHE = "${hfCacheDir}/hub";
          HF_HUB_ENABLE_HF_TRANSFER = "0";
        };

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "vllm";
          Group = "vllm";
          ExecStart = "${pkgs.python3-hf}/bin/hf download ${lib.escapeShellArg vcfg.model}";
          TimeoutStartSec = "2h";
        };
      };

      systemd.services.vllm = {
        description = "vLLM OpenAI-compatible inference server (${vcfg.model})";
        wantedBy = [ "multi-user.target" ];
        after = [
          "network-online.target"
          "vllm-model-download.service"
        ];
        requires = [ "vllm-model-download.service" ];
        wants = [ "network-online.target" ];

        environment = {
          HF_HOME = hfCacheDir;
          HUGGINGFACE_HUB_CACHE = "${hfCacheDir}/hub";
          HF_HUB_OFFLINE = "1";
          VLLM_CACHE_ROOT = "${compileCacheDir}/vllm";
          TRITON_CACHE_DIR = "${compileCacheDir}/triton";
          TORCHINDUCTOR_CACHE_DIR = "${compileCacheDir}/torch";
          CUDA_HOME = "${pkgs.cudatoolkit}";
          LD_LIBRARY_PATH = lib.makeLibraryPath [
            config.hardware.nvidia.package
            pkgs.cudaPackages.cuda_nvml_dev
            pkgs.cudaPackages.cuda_cudart
            pkgs.ncurses5
          ];
        };

        serviceConfig = {
          Type = "exec";
          User = "vllm";
          Group = "vllm";
          WorkingDirectory = stateDir;
          ExecStart = lib.concatStringsSep " " (
            [
              "${pkgs.vllm}/bin/vllm"
              "serve"
              (lib.escapeShellArg vcfg.model)
              "--host"
              "127.0.0.1"
              "--port"
              (toString vcfg.port)
              "--gpu-memory-utilization"
              (toString vcfg.gpuMemoryUtilization)
              "--max-model-len"
              (toString vcfg.maxModelLen)
              "--max-num-seqs"
              (toString vcfg.maxNumSeqs)
              "--enable-auto-tool-choice"
              "--tool-call-parser"
              vcfg.toolCallParser
            ]
            ++ lib.optionals (vcfg.servedModelName != null) [
              "--served-model-name"
              (lib.escapeShellArg vcfg.servedModelName)
            ]
            ++ map lib.escapeShellArg vcfg.extraFlags
          );
          Restart = "on-failure";
          RestartSec = "10s";
          TimeoutStartSec = "30min"; # first-time torch.compile can be slow
          # Conservative hardening — CUDA stacks dislike strict device rules.
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadWritePaths = [ stateDir ];
        };
      };

      # Manual unit: `sudo systemctl start vllm-clear-compile-cache.service`
      # Clears torch.compile / triton / vLLM compilation artifacts only.
      # Leaves HF-downloaded model weights untouched. Use after vLLM, torch,
      # or nvidia driver upgrades when you see cryptic kernel/IR errors.
      systemd.services.vllm-clear-compile-cache = {
        description = "Clear vLLM compile/triton/torch caches and restart vLLM";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "vllm-clear-compile-cache" ''
            set -euo pipefail
            ${pkgs.systemd}/bin/systemctl stop vllm.service || true
            rm -rf -- ${compileCacheDir}/vllm/* ${compileCacheDir}/torch/* ${compileCacheDir}/triton/*
            echo "cleared ${compileCacheDir}/{vllm,torch,triton}"
            ${pkgs.systemd}/bin/systemctl start vllm.service
          '';
        };
      };
    })

    (mkIf (vcfg.enable && vcfg.vhost != null) {
      services.nginx.virtualHosts."${vcfg.vhost}" = {
        forceSSL = true;
        enableACME = true;
        extraConfig = ''
          access_log /var/log/nginx/vllm-${vcfg.vhost}.access.log;
          error_log /var/log/nginx/vllm-${vcfg.vhost}.error.log;
          client_max_body_size 100m;
        '';
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString vcfg.port}";
          recommendedProxySettings = true;
          extraConfig = ''
            # SSE / long-poll streaming
            proxy_buffering off;
            proxy_cache off;
            proxy_http_version 1.1;
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
            chunked_transfer_encoding on;
          '';
        };
      };
    })
  ]);
}
