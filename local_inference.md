# Local Orchestrator: `local_inference.md`

This document defines how the Sensei uses a **local Llama runtime** (Ollama-compatible server) instead of any cloud provider.

## 1) Local-First Contract

- Inference endpoint must be local by default.
- No external AI API keys are required in default local mode.
- If the local Llama server is unavailable while local mode is selected, the app must:
  1. raise a visible UI warning,
  2. keep operating with rule-based fallback parsing,
  3. avoid cloud routing unless the user explicitly switches provider.

## 2) Endpoint Configuration

- Default base URL: `http://localhost:11434/v1`
- Health check path: `GET /models`
- Inference path: `POST /chat/completions`

Optional online providers (when selected in Settings):

- Claude: `https://api.anthropic.com/v1`
- Grok: `https://api.x.ai/v1`
- Gemini: `https://generativelanguage.googleapis.com/v1beta`
- ChatGPT: `https://api.openai.com/v1`

Runtime overrides:

- `LLAMA_BASE_URL` (optional)
- `LLAMA_MODEL` (optional)
- `LLM_PROVIDER` (optional: `llama|claude|grok|gemini|chatgpt`)
- `CLAUDE_API_KEY`, `GROK_API_KEY`, `GEMINI_API_KEY`, `OPENAI_API_KEY` (optional, required only for online modes)

Example:

```bash
flutter run \
  --dart-define=LLAMA_BASE_URL=http://localhost:11434/v1 \
  --dart-define=LLAMA_MODEL=llama3.3
```

## 3) Model Selection Policy

Primary model:

- `llama3.3` (preferred if available on local server)

Compatible alternate examples:

- `openchat-3.6`
- `llama3.2`

Resolution behavior:

1. Query local model list from `/v1/models`.
2. Use exact match or tagged variant (example: `llama3.3:latest`).
3. If primary is missing, switch to configured fallback list.
4. If no valid model exists, mark service unhealthy and show UI alert.

## 4) Heavy-Agent Fallback (RAM-Safe Mode)

Some specialized roles (example: "The Auditor") may exceed local RAM/VRAM budget.  
When this occurs, switch to a smaller quantized model profile.

Recommended sequence:

1. Try standard local model (`llama3.3`).
2. If latency spikes or memory pressure appears, switch to quantized local model:
   - `llama3.2:3b-instruct-q4_K_M`
   - or another local Q4/Q5 profile available in Ollama
3. If still unstable, use minimal local backup model:
   - `openchat-3.6` (or equivalent smaller local profile)
4. If local mode is required, continue fallback parsing instead of auto-switching to cloud.

Operational rule:

- Prefer lower quantization over service outage.
- Keep a stable local model online, even if quality is reduced.

## 5) Health Check and UI Signaling

The orchestrator must continuously validate local availability:

- Startup check during service initialization.
- Periodic checks while app is active.
- Manual user-triggered "Retry/Check" action.

UI behavior when unhealthy:

- Show warning banner on Home/Settings.
- Include endpoint and model mismatch details.
- Preserve local-only behavior and continue rule-based fallback.

## 6) Privacy and Audit Constraints

- Prompt/response payloads remain local when local mode is active.
- No telemetry forwarding of user content.
- No model requests to non-local hosts unless explicitly selected by the owner.
- All resulting ledger writes still flow through normal audit path (`last_rolo_id` linkage).

## 7) Implementation Notes (Current)

- Service: `lib/core/services/sensei_llm_service.dart`
- Initialization wiring: `lib/core/dojo_provider.dart`
- UI health alerts:
  - `lib/presentation/pages/dojo_home_page.dart`
  - `lib/presentation/pages/settings_page.dart`

