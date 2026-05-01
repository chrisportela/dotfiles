# local-llm

NixOS module that provisions a local LLM serving stack on a CUDA host. Currently
serves one model via **vLLM** with an OpenAI-compatible HTTP API, plus a Kokoro
TTS container retained from the previous Ollama-era setup.

## Purpose

Provide an "always-ready, fast" agentic inference endpoint on the LAN. Clients
that speak the OpenAI API (Claude Code, opencode, Cursor, LiteLLM, Open WebUI,
LangChain, …) can target this endpoint directly.

## Options

All options live under `chrisportela.local-llm`.

| Option | Type | Description |
|---|---|---|
| `enable` | bool | Enable the module (CUDA, nvidia driver, Kokoro TTS). |
| `vllm.enable` | bool | Enable the vLLM serving service. |
| `vllm.model` | string | HuggingFace repo ID to serve (e.g. `Qwen/Qwen2.5-Coder-14B-Instruct-AWQ`). |
| `vllm.toolCallParser` | str | Tool-call parser name registered in the running vLLM. Validated by vLLM at startup, not at Nix eval — the canonical list lives in `vllm/tool_parsers/__init__.py` of the pinned source. Examples: `hermes`, `llama3_json`, `mistral`, `pythonic`, `qwen3_coder`, `qwen3_xml`, `functiongemma`. |
| `vllm.gpuMemoryUtilization` | float | Fraction of GPU memory vLLM may use. Default `0.9`. |
| `vllm.maxModelLen` | int | Max context window in tokens. Default `8192`. KV-cache is pre-allocated based on this. |
| `vllm.port` | port | Port bound on `127.0.0.1`. Default `8000`. |
| `vllm.servedModelName` | str? | Short alias clients use in the OpenAI `model` field. Default: full repo ID. |
| `vllm.extraFlags` | [str] | Extra flags appended to `vllm serve`. |
| `vllm.vhost` | str? | If set, expose the API over HTTPS at this nginx virtualHost (ACME). vLLM has no auth — front with oauth-proxy or restrict network access before making public. |

## Dependencies

- NVIDIA GPU with driver, `hardware.nvidia.open = true`, and `nvidia-uvm`
  kernel module loaded at boot (set in `hosts/nixos/ada/hardware.nix`).
- `nixpkgs.config.cudaSupport = true` (set by this module).
- `services.nginx.enable = true` if `vllm.vhost` is set (enabled at the host
  level for ada).
- ACME configured at the host level if using `vllm.vhost`.

## State layout

```
/var/lib/vllm/
├── hf/            HF_HOME — model weights, tokenizers (big, keep)
│   └── hub/
└── cache/         compile caches — invalidated on upgrades
    ├── vllm/
    ├── torch/
    └── triton/
```

## Services

| Unit | Type | Purpose |
|---|---|---|
| `vllm-model-download.service` | oneshot | Prefetches the HF model before `vllm.service` starts. Idempotent — re-runs are cache checks. Runs on every boot. |
| `vllm.service` | exec | Runs `vllm serve` under a `vllm` system user. Depends on the download service. |
| `vllm-clear-compile-cache.service` | manual oneshot | Stops vLLM, clears `cache/{vllm,torch,triton}`, restarts vLLM. Run after upgrades. |

## Commands

```bash
# Status of the inference server and model download
systemctl status vllm.service
systemctl status vllm-model-download.service

# Tail logs
journalctl -u vllm.service -f
journalctl -u vllm-model-download.service -f

# Change model / flags → edit the host config block and rebuild:
nix build .#nixosConfigurations.ada.config.system.build.toplevel
# then on ada:
sudo nixos-rebuild switch --flake .#ada

# Clear compile caches after a vllm / torch / driver upgrade
# (does NOT delete downloaded model weights)
sudo systemctl start vllm-clear-compile-cache.service

# Nuke downloaded model weights (free disk, force re-download on next boot)
sudo systemctl stop vllm.service
sudo rm -rf /var/lib/vllm/hf
sudo systemctl start vllm-model-download.service

# Smoke-test the API locally
curl -s http://127.0.0.1:8000/v1/models | jq
curl -s http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"ada","messages":[{"role":"user","content":"hi"}]}'
```

## Gotchas

- **First request after a cold start is slow.** vLLM runs torch.compile on the
  first forward pass; subsequent requests use the cached kernels. A 30-minute
  `TimeoutStartSec` on `vllm.service` is intentional.
- **`HF_HUB_OFFLINE=1` on `vllm.service`** — once the prefetch service has run,
  vllm is prevented from making further HuggingFace network calls. If you
  change the model, the prefetch service picks up the new one *before* vllm
  restarts.
- **Public nginx vhost has no auth.** Pair with oauth-proxy, nginx basic-auth,
  or a Tailscale-only bind before exposing.
- **`extraFlags` is the escape hatch** for anything the typed options don't
  cover (quantization overrides, `--dtype`, `--enforce-eager`, etc.).
