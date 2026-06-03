# Ideogrammar — Ideogram 4 Prompt Editor

A single-file, no-build web app for composing structured **Ideogram 4** prompts. You lay out a scene visually on a 1000×1000 canvas, describe each element, and the app emits the exact JSON the Ideogram 4 model expects. It can also generate a whole setup from a one-line description via an LLM, and — in **ComfyUI mode** — render the prompt on your own ComfyUI server and show the result inline.

Everything lives in [`index.html`](index.html) (HTML + CSS + vanilla JS, no dependencies, no build step). [`comfy_proxy.py`](comfy_proxy.py) is an optional helper for ComfyUI mode.

## Features

- **Visual layout canvas** — drag/resize bounding boxes on a 1000×1000 grid (origin top-left). Each box is an element with a type, description, and color palette.
- **Structured prompt builder** — high-level description, style block (aesthetics, lighting, photo, medium, palette), background, and a reorderable list of elements.
- **Live JSON output** — syntax-highlighted, copy or download with one click.
- **Generate from text** — describe the image in plain language and an OpenAI-compatible LLM (OpenRouter or a local `llama.cpp` server) fills in the whole schema. Settings are stored in `localStorage`.
- **ComfyUI mode** — render the current prompt on your ComfyUI server using the bundled Ideogram 4 workflow, with every workflow parameter exposed and the result (plus live progress) shown in the editor.
- **Import / Reset / Download** — round-trip the prompt JSON.

## Quick start

Open `index.html` in a browser. That's it for the **Manual** workflow (build the prompt, copy/download the JSON, paste it into Ideogram or ComfyUI yourself).

## Modes

A toggle in the header switches between:

- **Manual** (default) — no server calls. Build the prompt and copy/download the JSON. Behaves exactly like a plain prompt editor.
- **ComfyUI** — adds a parameters panel and renders on your ComfyUI server, displaying the image inline.

## Prompt JSON shape

```json
{
  "high_level_description": "one vivid sentence describing the whole image",
  "style_description": {
    "aesthetics": "...", "lighting": "...", "photo": "...", "medium": "...",
    "color_palette": ["#RRGGBB", "..."]
  },
  "compositional_deconstruction": {
    "background": "...",
    "elements": [
      { "type": "obj|subject|text|logo|bg", "bbox": [x1, y1, x2, y2], "desc": "...", "color_palette": ["#RRGGBB"] }
    ]
  }
}
```

Coordinates are a 1000×1000 space, origin top-left, `bbox = [x1, y1, x2, y2]`.

## Generate from text (LLM)

Click **✨ Generate from text**, open **Model provider settings**, and configure an OpenAI-compatible endpoint:

- **OpenRouter** — base URL `https://openrouter.ai/api/v1`, your API key, a model like `anthropic/claude-3.5-sonnet`.
- **Local llama.cpp** — run `llama-server` with CORS enabled; base URL `http://<host>:8081/v1`.

The model returns the full schema, which you can then edit visually. Settings are saved in your browser only.

## ComfyUI mode

ComfyUI mode renders the current prompt on your server with the bundled Ideogram 4 workflow ([`workflow.json`](workflow.json), embedded in the page). The left panel exposes every meaningful parameter — server URL, aspect ratio, megapixels, quality preset (Quality/Default/Turbo), seed (+ randomize), guidance CFG, sampler, CFG-override, batch size, and the diffusion / unconditional / VAE / CLIP model names. The editor's prompt JSON is injected into the positive-prompt node on every render. Results and live progress appear in the middle panel.

### The CORS problem (and why the proxy exists)

A browser will not let a page read responses from a **different origin** unless that server sends CORS headers. ComfyUI sends none by default. (Server-to-server clients — like a Python script using `httpx` — never hit this, because CORS is a browser-only rule.) So a browser-based editor needs one of:

**Option A — run the bundled proxy (recommended; no ComfyUI changes):**

```bash
python comfy_proxy.py
# defaults: serves http://localhost:8189/ , forwards to http://192.168.2.33:8188
```

Then open **http://localhost:8189/**, switch to **ComfyUI** mode, and leave the **Server URL blank** (blank = same origin). The proxy serves the editor and forwards all API calls + the `/ws` progress WebSocket to ComfyUI, so the browser only ever talks to one origin.

Proxy flags:

| Flag | Default | Purpose |
|------|---------|---------|
| `--comfy URL` | `http://192.168.2.33:8188` | ComfyUI base URL |
| `--host ADDR` | `127.0.0.1` | bind address (`0.0.0.0` to expose on LAN) |
| `--port N` | `8189` | port to serve on |
| `--html PATH` | `./index.html` | page to serve |
| `--verbose` | off | log every request |

It is stdlib-only (Python 3.8+) — nothing to install.

**Option B — enable CORS in ComfyUI:**

```bash
python main.py --listen --enable-cors-header
```

Then point the editor's **Server URL** straight at ComfyUI (e.g. `http://192.168.2.33:8188`).

### Test connection

The **Test connection** button in the ComfyUI panel pings `/system_stats` and reports whether the server is reachable (and its ComfyUI version), or explains what's wrong (down / wrong URL / CORS-blocked).

## Files

| File | Purpose |
|------|---------|
| [`index.html`](index.html) | The entire app — editor, canvas, LLM generation, ComfyUI mode. |
| [`comfy_proxy.py`](comfy_proxy.py) | Optional stdlib proxy: serves the page + forwards HTTP and the WebSocket to ComfyUI (same-origin, no CORS flags). |
| [`workflow.json`](workflow.json) | The Ideogram 4 ComfyUI workflow (API format) the render mode is built around; also embedded in `index.html`. |

## Notes

- Rendered images come back as ComfyUI `temp` files (from the `PreviewImage` node); the editor handles that automatically.
- LLM and ComfyUI settings persist in `localStorage` (per browser).
- Works over plain HTTP on a LAN; clipboard copy falls back to a manual path on insecure origins.
