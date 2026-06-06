# Ideogrammar — Ideogram 4 Prompt Editor

A single-file, no-build web app for composing structured **Ideogram 4** prompts. You lay out a scene visually on a 1000×1000 canvas, describe each element, and the app emits the exact JSON the Ideogram 4 model expects. It can also generate a whole setup from a one-line description via an LLM, and — in **ComfyUI mode** — render the prompt on your own ComfyUI server and show the result inline.

Everything lives in [`index.html`](index.html) (HTML + CSS + vanilla JS, no dependencies, no build step). [`comfy_proxy.py`](comfy_proxy.py) is an optional helper for ComfyUI mode.

## Features

- **Tiled, draggable workspace** — the main area is a GridStack grid of resizable/draggable windows (Prompt builder, Layout canvas, JSON output, Rendered output). Drag a window by its title bar, resize from the edges; the arrangement is saved per browser. A header picker offers space-maximizing presets — *Sidebar + split* (builder sidebar, canvas + render side by side, JSON strip below), *Three columns*, *Render focus*, and *Quadrants*. GridStack is bundled locally (no CDN), served by the proxy.
- **Visual layout canvas** — drag/resize bounding boxes on a 1000×1000 grid (origin top-left). Each box is an element with a type, description, and color palette. The canvas reshapes to the selected aspect ratio.
- **Structured prompt builder** — high-level description, style block (aesthetics, lighting, photo, medium, palette), background, and a reorderable list of elements.
- **Live JSON output** — syntax-highlighted, copy or download with one click.
- **Generate from text** — describe the image in plain language and an OpenAI-compatible LLM (OpenRouter or a local `llama.cpp` server) fills in the whole schema. Settings are stored in `localStorage`.
- **Refine** — ask the LLM to adjust the current setup with a plain-language change (e.g. "make it a lighter composition"); it rewrites the whole setup while keeping everything the request doesn't touch.
- **ComfyUI mode** — render the current prompt on your ComfyUI server using the bundled Ideogram 4 workflow, with every workflow parameter exposed and the result (plus live progress) shown in the editor. Renders collect in a gallery with a full-size viewer, and can be saved permanently.
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

## Settings (⚙)

The **⚙ Settings** button (header) opens one dialog for everything not tied to a specific render:

- **Text-generation model (LLM)** — provider (OpenRouter / local llama.cpp), base URL, API key, model. **Save named presets** of these so switching endpoints doesn't lose the model name — pick a preset from the dropdown to restore it.
- **Vectorizer** — mask method (SAM / heuristic / none) and flatness threshold.
- **Setups & library** — save/load/delete named **setups** (the full prompt builder state + render parameters).

## Generate from text (LLM)

Configure a provider in **⚙ Settings** (OpenAI-compatible):

- **OpenRouter** — base URL `https://openrouter.ai/api/v1`, your API key, a model like `anthropic/claude-3.5-sonnet`.
- **Local llama.cpp** — run `llama-server` with CORS enabled; base URL `http://<host>:8081/v1`.

Then click **✨ Generate from text**, describe the image, and the model returns the full schema, which you can edit visually. Settings/presets are saved in your browser only.

## Refine (LLM)

Click **🪄 Refine** to adjust the *current* setup with a natural-language change instead of starting over. Describe a change (e.g. "make it a lighter composition", "move the title to the bottom", "swap the palette to autumn tones") and the model rewrites the **entire** setup — style, background and every positioned element — to reflect it while preserving everything the request doesn't touch. Per-element vectorize modes are carried over by position. Quick-suggestion chips are provided. You can also refine straight from a render: open it in the viewer and press **🪄 Refine** to load that render's setup and adjust it.

## Setups & library

A **setup** is the whole prompt builder state (description, style, background, positioned elements with per-element vectorize modes) plus the render parameters. Save the current one from **⚙ Settings → Setups & library**, and reload it anytime. Every render also captures its setup: open it in the viewer and press **⤵ Load setup** to restore exactly the prompt + settings that produced it. Stored in `localStorage`.

## ComfyUI mode

ComfyUI mode renders the current prompt on your server with the bundled Ideogram 4 workflow ([`workflow.json`](workflow.json), embedded in the page). The left panel exposes every meaningful parameter — connection (proxy vs. direct), scheduler workflow, aspect ratio, megapixels, quality preset (Quality/Default/Turbo), seed (+ randomize), guidance CFG, sampler, CFG-override, batch size, and the diffusion / unconditional / VAE / CLIP model names. The **scheduler workflow** selector switches between the stock *Ideogram 4 default* (`Ideogram4Scheduler`) and a community *simple scheduler* variant (`ModelSamplingAuraFlow` shift + `BasicScheduler` "simple" + euler), which some find gives better results; switching also sets the matching recommended sampler. The editor's prompt JSON is injected into the positive-prompt node on every render. Results and live progress appear in the middle panel. A **Test connection** button reports whether the server is reachable (and its version) or what's wrong.

The middle panel also reshapes to the selected **aspect ratio** so the layout preview matches the real canvas (coordinates stay normalized `0–1000` per axis).

**Vectorize to SVG (local, experimental).** The **⬡ Vectorize → SVG** button (in the Rendered output tile, and in the full-image viewer for any gallery item) converts a render to a *hybrid* SVG: flat regions (text, logos, and `obj` regions that pass a flatness heuristic) are traced to vector paths with [VTracer](https://github.com/visioncortex/vtracer); photographic regions (`subject`, `bg`) stay as an embedded raster base. Routing uses the element types from the prompt plus a per-region reconstruction-error test. Each vector overlay is **clipped to the element's actual shape** (so vector text sits over the photo as glyphs, not as a rectangle) using a mask — **SAM if you've configured it**, otherwise a built-in foreground heuristic. The result opens in the viewer with a download link.

The **⚙ settings** dialog (next to the Vectorize button) lets you pick the **mask method** — SAM, the foreground heuristic (the older, faster method), or no masking (trace the whole box) — and a **flatness threshold** for `Auto` regions. For finer control, each element card has a **Vectorize** dropdown: *Auto (by type)*, *Always vector*, or *Never (keep raster)* — handy when the automatic routing vectorizes the wrong part.

This runs in `comfy_proxy.py`'s `/vectorize` endpoint and needs extra Python packages on the proxy host (kept in a venv; the proxy lazily imports them, so the rest of the app is unaffected if they're absent):

```bash
python3 -m venv .venv
.venv/bin/pip install vtracer pillow opencv-python-headless numpy
# point the service at that interpreter:
PYTHON="$PWD/.venv/bin/python" ./comfy_proxy.sh install-service
```

Photoreal subjects don't meaningfully vectorize (kept raster by design), so output is a mixed vector+raster SVG.

#### Optional: higher-quality masks via Segment Anything (SAM)

If `SAM_CHECKPOINT` is set, the proxy uses [SAM](https://github.com/facebookresearch/segment-anything) for region masks instead of the built-in foreground heuristic. Install it into the same venv and download a checkpoint:

```bash
# CPU build of PyTorch (~200 MB) — simplest, no CUDA matching needed
.venv/bin/pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu
.venv/bin/pip install "git+https://github.com/facebookresearch/segment-anything.git"

# vit_b checkpoint (~358 MB), smallest/fastest
mkdir -p models
curl -L -o models/sam_vit_b_01ec64.pth \
  https://dl.fbaipublicfiles.com/segment_anything/sam_vit_b_01ec64.pth
```

Point the service at it — `install-service` writes the env vars into the systemd unit when they're set, so it persists across restarts:

```bash
SAM_CHECKPOINT="$PWD/models/sam_vit_b_01ec64.pth" SAM_MODEL_TYPE=vit_b \
  PYTHON="$PWD/.venv/bin/python" ./comfy_proxy.sh install-service
```

If SAM fails to load it silently falls back to the heuristic, so the feature never hard-breaks.

> **Speed (CPU):** the CPU build is not fast — the first vectorize after a (re)start pays a one-time model-load cost (~a minute), and each region then takes a few seconds. Fine for an occasional manual action. For GPU speed (it shares the card with ComfyUI; the code auto-selects CUDA when available), install a CUDA build instead and restart:
>
> ```bash
> .venv/bin/pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121  # match your CUDA
> systemctl --user restart comfy_proxy.service
> ```
>
> `vit_l` / `vit_h` checkpoints give sharper masks at higher cost. `models/` and `.venv/` are gitignored.

**Gallery & saving.** Every render is added to a **History** strip below the result; click the result image or any thumbnail to open a full-size **viewer modal** with prev/next (arrow keys), **rotate 90° CW/CCW** (saved per item; applied to the view, the download, the gallery thumbnail, and vectorize), seed/aspect info, and a download link. By default renders are ComfyUI **temp** files, so the gallery is session-only. Tick **Save renders permanently** to switch the output node to `SaveImage` (files land in ComfyUI's `output/` as `ideogrammar_*.png`); those renders persist in the gallery across reloads (stored in `localStorage`, last 60). **Clear** empties the gallery list only — it never deletes files from `output/`.

### The CORS problem (and why the proxy exists)

A browser will not let a page read responses from a **different origin** unless that server sends CORS headers. ComfyUI sends none by default. (Server-to-server clients — like a Python script using `httpx` — never hit this, because CORS is a browser-only rule.) So a browser page that loads from one place and calls ComfyUI somewhere else is blocked.

The proxy fixes this by being **both** the web server that serves the editor **and** the forwarder to ComfyUI — so the browser only ever talks to *one* origin. The editor defaults to talking to whatever origin served it, so when you open it *through the proxy*, it just works.

**Option A — run the bundled proxy (recommended; no ComfyUI changes):**

Use the start/stop helper on a host that can reach ComfyUI:

```bash
./comfy_proxy.sh start      # start (listens on 0.0.0.0:8189, forwards to ComfyUI)
./comfy_proxy.sh status     # is it running? what address?
./comfy_proxy.sh stop
./comfy_proxy.sh restart
./comfy_proxy.sh logs       # tail the log
```

It prints the address to open, e.g. `http://192.168.2.35:8189/`. Open **that** address in your browser (from any machine on the LAN), switch to **ComfyUI** mode, and leave **"Connect directly to ComfyUI" unchecked**. The green line under it confirms renders go to the proxy. The proxy forwards all API calls + the `/ws` progress WebSocket, so there's no CORS.

Override defaults with environment variables:

```bash
COMFY_URL=http://192.168.2.33:8188 PROXY_HOST=0.0.0.0 PROXY_PORT=8189 ./comfy_proxy.sh start
```

Or run the Python directly (same effect, no PID/log management):

```bash
python comfy_proxy.py --comfy http://192.168.2.33:8188 --host 0.0.0.0 --port 8189
```

| Flag | Default | Purpose |
|------|---------|---------|
| `--comfy URL` | `http://192.168.2.33:8188` | ComfyUI base URL |
| `--host ADDR` | `127.0.0.1` | bind address (`0.0.0.0` to expose on LAN) |
| `--port N` | `8189` | port to serve on |
| `--html PATH` | `./index.html` | page to serve |
| `--verbose` | off | log every request |

Both are stdlib-only (Python 3.8+) — nothing to install.

> **Common mistake:** serving the editor with a *plain* static server (e.g. `python -m http.server`) and opening that. A static server hands out `index.html` but 404s on `/system_stats`, `/prompt`, etc. — so renders fail. The editor must be served by `comfy_proxy.py`, which forwards those calls.

#### Run it as a background service (systemd, survives logout/reboot)

```bash
./comfy_proxy.sh install-service     # install + enable + start (per-user, no sudo)
```

This writes a systemd **user** unit, enables it at boot, starts it, and turns on linger so it keeps running when you log out. Manage it with standard systemd:

```bash
systemctl --user status  comfy_proxy.service
systemctl --user restart comfy_proxy.service
systemctl --user stop    comfy_proxy.service
journalctl --user -u comfy_proxy.service -f      # live logs
./comfy_proxy.sh uninstall-service               # remove it
```

Set host/port/target at install time with the same env vars:

```bash
COMFY_URL=http://192.168.2.33:8188 PROXY_HOST=0.0.0.0 PROXY_PORT=8189 ./comfy_proxy.sh install-service
```

For a **system-wide** service instead (starts at boot regardless of any login; uses sudo):

```bash
SERVICE_SCOPE=system ./comfy_proxy.sh install-service
# manage with: sudo systemctl {status|restart|stop} comfy_proxy.service
```

**Option B — connect directly (enable CORS in ComfyUI):**

```bash
python main.py --listen --enable-cors-header
```

Then in the editor, tick **"Connect directly to ComfyUI"** and enter its URL (e.g. `http://192.168.2.33:8188`). No proxy needed in this mode.

### Test connection

The **Test connection** button in the ComfyUI panel pings `/system_stats` and reports whether the server is reachable (and its ComfyUI version), or explains what's wrong (down / wrong URL / CORS-blocked).

## Files

| File | Purpose |
|------|---------|
| [`index.html`](index.html) | The entire app — editor, canvas, LLM generation, ComfyUI mode. |
| [`comfy_proxy.py`](comfy_proxy.py) | Stdlib proxy: serves the page + local asset files (e.g. `vendor/`), forwards HTTP and the WebSocket to ComfyUI (same-origin, no CORS flags), and hosts the `/vectorize` endpoint (optional `vtracer`/`pillow` deps). |
| [`comfy_proxy.sh`](comfy_proxy.sh) | start/stop/status/restart/logs helper, plus `install-service`/`uninstall-service` to run it as a background systemd service. |
| [`workflow.json`](workflow.json) | The Ideogram 4 ComfyUI workflow (API format) the render mode is built around; also embedded in `index.html`. |
| [`vendor/`](vendor/) | Bundled third-party assets (GridStack JS/CSS) served locally by the proxy, so the tiled layout works without a CDN. |

## Notes

- Rendered images come back as ComfyUI `temp` files (from the `PreviewImage` node); the editor handles that automatically.
- LLM and ComfyUI settings persist in `localStorage` (per browser).
- Works over plain HTTP on a LAN; clipboard copy falls back to a manual path on insecure origins.
