# Gemini Thought Signature Proxy

> Customised fork of [`gemini-thought-signature-proxy`](https://github.com/john-raymon/gemini-thought-signature-proxy) — deployed on Kubernetes behind Traefik.

Bypasses Google's `thought_signature` requirement so Gemini models work with **VS Code Copilot BYOK** in Agent mode.

```
400 INVALID_ARGUMENT: Function call is missing a thought_signature in functionCall parts.
```

---

## How it works

1. VS Code Copilot sends a chat request to the proxy (`gemini-proxy.skarvelis.gr`)
2. The proxy strips the Copilot-specific model ID suffix, maps it to Google's actual model ID, injects `skip_thought_signature_validator`, and forwards to Google
3. Google responds normally
4. The proxy streams the response back to VS Code

---

## Supported models

| VS Code model ID | → Google model ID | Patching | Status |
|---|---|---|---|
| `models/gemini-3.1-pro-preview-YOURPASSPHRASE` | `gemini-3.1-pro-preview` | Injects bypass | ✅ |
| `models/gemini-3-flash-preview-YOURPASSPHRASE` | `gemini-3-flash-preview` | Injects bypass | ✅ |
| `models/gemini-3.1-flash-lite-YOURPASSPHRASE` | `gemini-3.1-flash-lite` | Injects bypass | ✅ |
| `models/gemini-3.5-flash-YOURPASSPHRASE` | `gemini-3.5-flash` | Injects bypass | ✅ |
| `models/gemini-3.5-flash-nopatch-YOURPASSPHRASE` | `gemini-3.5-flash` | Skipped (`-nopatch-`) | ✅ |

> The `-YOURPASSPHRASE` suffix is a **passphrase** configured via the `PASSPHRASE` environment variable (defaults to `-customtools`). The proxy rejects requests whose model ID does not start with `models/` or does not end with the passphrase — this prevents unauthorised use of the proxy.

---

## Quick Start

### 1. Create `.env` file

```bash
# .env — place in project root
PASSPHRASE=-YOURPASSPHRASE
```

### 2. Build & push

```bash
docker build -t localhost:32000/gemini-proxy:latest .
docker push localhost:32000/gemini-proxy:latest
```

### 3. Deploy to Kubernetes

```bash
# Create namespace + deploy Helm chart
microk8s.helm3 upgrade --install gemini-proxy ./charts/gemini-proxy-k8s \
  --namespace gemini-proxy --create-namespace

# Create secret from .env
microk8s.kubectl create secret generic gemini-proxy-env \
  --from-env-file=.env -n gemini-proxy

# Restart to pick up new secret (if updated)
microk8s.kubectl rollout restart deploy/gemini-proxy-gemini-proxy-k8s -n gemini-proxy
```

### 4. Configure VS Code

Edit `chatLanguageModels.json` (Cmd+Shift+P → `Chat: Open Language Models (JSON)`):

```json
{
  "name": "MyGemini",
  "vendor": "customendpoint",
  "apiKey": "${input:chat.lm.secret.YOUR_SECRET_ID}",
  "apiType": "chat-completions",
  "models": [
    {
      "id": "models/gemini-3.1-pro-preview-YOURPASSPHRASE",
      "name": "Gemini 3.1 Pro Preview",
      "url": "https://gemini-proxy.skarvelis.gr/v1beta/openai/",
      "toolCalling": true,
      "vision": true,
      "maxInputTokens": 2000000,
      "maxOutputTokens": 8192
    },
    {
      "id": "models/gemini-3-flash-preview-YOURPASSPHRASE",
      "name": "Gemini 3 Flash Preview",
      "url": "https://gemini-proxy.skarvelis.gr/v1beta/openai/",
      "toolCalling": true,
      "vision": true,
      "maxInputTokens": 1000000,
      "maxOutputTokens": 8192
    },
    {
      "id": "models/gemini-3.1-flash-lite-YOURPASSPHRASE",
      "name": "Gemini 3.1 Flash Lite",
      "url": "https://gemini-proxy.skarvelis.gr/v1beta/openai/",
      "toolCalling": true,
      "vision": true,
      "maxInputTokens": 1000000,
      "maxOutputTokens": 8192
    },
    {
      "id": "models/gemini-3.5-flash-YOURPASSPHRASE",
      "name": "Gemini 3.5 Flash",
      "url": "https://gemini-proxy.skarvelis.gr/v1beta/openai/",
      "toolCalling": true,
      "vision": true,
      "maxInputTokens": 1000000,
      "maxOutputTokens": 8192
    }
  ]
}
```

Then add your Google API key via `Chat: Manage Language Models` in the command palette.

---

## Technical Details

### Path routing

VS Code appends `v1/chat/completions` to the base URL. With base `https://gemini-proxy.skarvelis.gr/v1beta/openai/`, requests arrive at `/v1beta/openai/v1/chat/completions`. The proxy rewrites this to Google's `/v1beta/openai/chat/completions`.

### Model ID transformation

```
models/gemini-3.5-flash-YOURPASSPHRASE          ← VS Code sends this
         ↓  strip models/ prefix
         ↓  strip -YOURPASSPHRASE passphrase
gemini-3.5-flash                                ← forwarded to Google

models/gemini-3.5-flash-nopatch-YOURPASSPHRASE  ← Optional: bypass injection
         ↓  strip models/ prefix & -YOURPASSPHRASE
         ↓  strip -nopatch-
gemini-3.5-flash                                ← forwarded untouched to Google
```

### Passphrase protection

The `PASSPHRASE` env var (from `gemini-proxy-env` secret, defaults to `-customtools` if unset) is used as a required suffix on all model IDs. Requests with model IDs missing the passphrase or not starting with `models/` are rejected with HTTP 400. This prevents unauthorised use of the proxy.

### Thought signature injection

For every `assistant` message containing `tool_calls`, the proxy injects:

```json
"extra_content": { "google": { "thought_signature": "skip_thought_signature_validator" } }
```

This is Google's documented bypass sentinel.

#### Skipping signature injection (`-nopatch-`)

If a model ID contains `-nopatch-` (e.g. `models/gemini-3.5-flash-nopatch-YOURPASSPHRASE`), the proxy skips thought signature injection entirely and forwards the messages untouched, while stripping `-nopatch-` before forwarding to Google.

### Ingress security

The Traefik ingress only routes paths starting with `/v1beta` — scanner traffic (`/wp-admin`, `/.env`, etc.) is blocked at the edge.

---

## File overview

```
.
├── Dockerfile              # Node 22 Alpine, runs proxy.js
├── proxy.js                # The proxy server (Express)
├── cli.js                  # Entry point
├── package.json            # Dependencies (express, node-fetch)
├── .env                    # PASSPHRASE (not committed)
├── charts/
│   └── gemini-proxy-k8s/   # Helm chart
│       ├── Chart.yaml
│       ├── values.yaml
│       ├── .helmignore
│       └── templates/
│           ├── _helpers.tpl
│           ├── deployment.yaml
│           ├── service.yaml
│           └── ingress.yaml
└── README.md
```

## References

- [Google Thought Signatures docs](https://ai.google.dev/gemini-api/docs/thought-signatures)
- [Google OpenAI Compatibility](https://ai.google.dev/gemini-api/docs/openai)
- [Original npm package](https://www.npmjs.com/package/gemini-thought-signature-proxy)