---
name: figma-design-extraction
description: >
  Extract a Figma design (tokens, assets, layout) and rebuild it as a coded SPA
  for a demo. Use when you have access to a customer's Figma file and need to
  recreate its screens in React/Vue/Angular (e.g. for a Power Pages or Code App
  demo). Covers Dev Mode MCP setup, the REST fallback, asset extraction, access
  tiers, rate limits, and the "more screens than there really are" trap. Use when
  the user says "extract the Figma", "rebuild this design", "Figma to code",
  "Figma MCP", "get the design tokens", "Dev Mode MCP not showing".
version: 1.0.0
author: Grant Readings
applyTo: ""
tags:
  - figma
  - design-to-code
  - mcp
  - demo
  - assets
  - spa
---

# Figma design extraction (for demo rebuilds)

Recreate a customer's Figma design as a coded SPA. The goal is **faithful,
offline-capable extraction**: pull the real design tokens, assets, and layout so
you can rebuild the screens in your target stack without endlessly round-tripping
to Figma.

> **Sanitisation note:** never commit a customer's Figma **file key**, personal
> access **token**, tenant URLs, or customer names into a shared repo. The file
> key lives in local config; the token lives in a gitignored `.env`.

---

## 0. The one decision that changes everything: access tier

| Your seat | What you get | Approach |
|---|---|---|
| **Editor / Dev seat** | Dev Mode + the **MCP server** → clean code, real tokens, downloadable assets, **no rate limits** | **Use the MCP.** This skill's happy path. |
| **Reader only** | REST API + screenshots only — rate-limited, fragmented vectors, poor image fidelity | Use the **REST fallback** (§5) and lean on designer-supplied screenshots. |

Confirm the tier first (`whoami` on the remote MCP, or just check what the desktop
app lets you do). If you can switch a file to **Dev Mode** (the `</>` toggle), you
have the access you need.

---

## 1. Enable the Dev Mode MCP server (the happy path)

The MCP renders through the desktop app locally, so there are **no REST rate
limits** and you get structured code + tokens + assets per node.

**Steps (desktop server — preferred):**
1. Open the file in the **Figma desktop app** (not the browser).
2. Switch to **Dev Mode**: press `Shift + D`, or click the `</>` toggle.
3. Click empty canvas (nothing selected) → in the **right sidebar** find the
   **MCP** section → ensure **Server status: Enabled** and **Image source:
   Local server**.
4. The server listens at `http://127.0.0.1:3845/mcp`.

**Register it in VS Code** (`.vscode/mcp.json`):
```json
{
  "servers": {
    "Figma Desktop": { "type": "http", "url": "http://127.0.0.1:3845/mcp" }
  }
}
```

### Gotchas that cost real time
- **The MCP toggle is NOT in the Preferences menu.** It is in the **Dev Mode
  right sidebar**. Don't hunt through Preferences.
- **Trial Dev Mode may be pending admin review.** If you see a toast like *"Enjoy
  Dev Mode for up to 3 days while waiting for admin review"*, the local MCP toggle
  can be **unavailable until an admin approves**. Don't keep looking for it — use
  the REST fallback meanwhile, or wait for approval.
- **Verify the port is live:** a bare request returns HTTP 400 when the server is
  up (it wants a proper MCP handshake):
  ```pwsh
  try { Invoke-WebRequest 'http://127.0.0.1:3845/mcp' -Method Head -TimeoutSec 5 | Out-Null; 'REACHABLE' }
  catch { if ($_.Exception.Response.StatusCode.value__) { 'UP (handshake needed)' } else { 'NOT LISTENING — enable the toggle' } }
  ```
- **Remote server** (`https://mcp.figma.com/mcp`) is the fallback if you can't run
  the desktop app: browser OAuth, works on any seat, but you must pass `fileKey` +
  `nodeId` to every call (no "current selection").

---

## 2. The MCP tools you'll actually use

| Tool | Returns | Use for |
|---|---|---|
| `get_metadata` (nodeId) | XML structure: node IDs, names, types, sizes | Find a screen's frame IDs. **No nodeId → lists the document's pages.** |
| `get_design_context` (nodeId) | React+Tailwind reference code + a screenshot + **asset download URLs** | The primary design-to-code call. Adapt the code to your stack. |
| `get_variable_defs` (nodeId) | The design **tokens** (font family, colours, spacing, type ramp) | Fill an empty `tokens.css`. Works on all plans. |
| `get_screenshot` (nodeId) | A PNG of the node | Visual reference / fidelity check. |

**Discovery → tokens → per-screen workflow:**
1. `get_metadata` on the prototype page → note each screen's top-level frame ID.
2. `get_variable_defs` on a representative screen → write the real tokens.
3. For each screen: `get_design_context` → adapt code, **download its assets**
   (§3), rebuild in your stack.

### The Code Connect prompt — skip it for demo rebuilds
The **first** `get_design_context` call often returns a script asking *"set up
Code Connect to map components?"*. Code Connect maps an **existing** component
library to Figma — irrelevant when you're rebuilding from scratch for a demo.
**Decline / proceed** — the code is still returned. (On the desktop tool, just
call `get_design_context` again; it does not accept a `disableCodeConnect` param —
that's remote-only.)

---

## 3. Downloading assets (the part that fixes "images look rubbish")

`get_design_context` embeds asset URLs like
`http://localhost:3845/assets/<hash>.png` (or `.svg`). These are served by the
**local** MCP server — **no rate limits**. Download them while the desktop app +
MCP server are running:

```pwsh
$dir = "app/src/assets"
New-Item -ItemType Directory -Force -Path "$dir/img","$dir/icons" | Out-Null
Invoke-WebRequest 'http://localhost:3845/assets/<hash>.svg' -OutFile "$dir/icons/logo.svg"
Invoke-WebRequest 'http://localhost:3845/assets/<hash>.png' -OutFile "$dir/img/hero.png"
```

Tips:
- **Icons / logos / maps are usually SVG**; photos are PNG. Prefer the SVG.
- A "background image" may be a **single vector node** (e.g. a world map). If your
  first guess looks wrong, `get_metadata` the screen and look for a large `<vector>`
  — `get_design_context` on that node gives its SVG URL.
- If an asset is genuinely fragmented (many tiny vectors), recreate it with inline
  SVG/CSS rather than stitching fragments.

---

## 4. Navigation & scoping — read this before you over-build

- **URL → node id:** `figma.com/design/:fileKey/:fileName?node-id=1-2` → `nodeId`
  is `1:2` (convert `-` to `:`). The `fileKey` is the segment after `/design/`.
- **"The Figma has way more screens than the PDF!"** — Prototypes use **one frame
  per interaction state** (default, hover, each click-step). 30 artboards often
  collapse to ~10 distinct screens. **Group frames by identical text content**:
  if six "Agent" frames have the same copy with rising node counts, they're the
  click-through steps of **one** screen — build it once.
- **A designer-supplied PDF / screenshot set is gold.** It's the visual ground
  truth and often beats fighting the API for pixel fidelity. Catalogue it and
  build against it.
- **No published styles?** A file may have an empty styles list (nothing was
  published to a library). Then tokens come from `get_variable_defs`, not the
  `/styles` endpoint.

---

## 5. REST API fallback (reader-only, bulk, or offline)

When the MCP isn't available, use the REST API with a **personal access token**.

**Generate the PAT:** Figma → Settings → Security → Personal access tokens.
Grant read scopes: `file_content`, `file_dev_resources`, `library_assets`,
`library_content`, `file_variables`, `current_user`. **Dev tokens can be
short-lived (e.g. 3 days)** — generate the longest allowed and **harvest early**.
Store it in a gitignored `.env` as `FIGMA_TOKEN`, never in source.

```pwsh
$h = @{ 'X-Figma-Token' = $env:FIGMA_TOKEN }
# Verify
Invoke-RestMethod 'https://api.figma.com/v1/me' -Headers $h
# Full-file OFFLINE SNAPSHOT — pull this FIRST (exact geometry/text/colours).
Invoke-RestMethod "https://api.figma.com/v1/files/<your-file-key>" -Headers $h -TimeoutSec 180 |
  ConvertTo-Json -Depth 100 -Compress | Out-File figma-raw/file-full.json -Encoding utf8
```

### REST pain points (all real)
- **`/images` exports rate-limit hard:** batched requests hit 429, and big frames
  return **400 "render timeout"**. Export **one frame at a time**, with a **scale
  fallback** (`scale=2` → retry `scale=1`) and a 429 backoff. Skip-existing makes
  it resumable.
- **`/files/{key}/variables/local` needs an Enterprise org** — otherwise it 403s
  with *"Incorrect account type"*. Use the MCP `get_variable_defs` instead.
- **Offline-first:** the full-file JSON snapshot lets you keep rebuilding after the
  token / dev access expires. Pull it before you do anything else.

---

## 6. Rebuild workflow (end to end)

1. **Verify access tier** → choose MCP (editor) or REST (reader).
2. **Enable the MCP** (§1) or **generate the PAT + pull the snapshot** (§5).
3. **`get_metadata`** the prototype page → list screen frame IDs; group duplicate
   interaction states into distinct screens.
4. **`get_variable_defs`** → write the real design tokens into your token file.
5. **Per screen:** `get_design_context` → adapt the code to your stack (don't ship
   raw React+Tailwind into a non-Tailwind project); **download its assets** (§3);
   build the component; verify against `get_screenshot` / the designer's PDF.
6. **Shared shell first** (nav rail, top bar, layout) — it pays back on every
   screen.
7. **Model the data once.** Put demo data in a single typed module shaped like your
   eventual backend (e.g. Dataverse entities) so the mock→live swap is localised.

---

## Key takeaways
- **Editor access + desktop Dev Mode MCP is the simple path** — clean code, real
  tokens, downloadable assets, no rate limits.
- **The MCP toggle lives in the Dev Mode sidebar, not Preferences** — and may be
  gated behind admin review on a trial.
- **Pull a full-file JSON snapshot early** so the rebuild survives token/access
  expiry.
- **One frame per interaction state** — don't mistake prototype states for extra
  screens.
- **Never commit the file key, token, tenant, or customer name** to a shared repo.

---

> Not Microsoft-endorsed. Provided as-is.
