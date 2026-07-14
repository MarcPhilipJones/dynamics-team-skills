---
name: embedding-advanced-widget
description: >
  Embed a third-party JavaScript chat widget (or any external JS widget) on
  Power Pages Code Sites (v2 data model) without CSP violations. Covers: 
  self-hosting external scripts as Power Pages web files, React component
  wrapper for SPA pages, Liquid/web-template injection for server-rendered
  pages (Profile, Search, etc.), post-deploy API patching for Header/Footer
  templates, and avoiding the CSP disaster of HTTP/Content-Security-Policy
  site settings. Use when: adding any external widget, chat bubble, analytics
  script, or third-party JS to a Power Pages Code Site.
  EXCEPTION: for the D365 Omnichannel live chat widget, self-hosting the
  bootstrapper does NOT work (it pulls further oc-cdn script chunks that stay
  script-src blocked) -> use the omnichannel-custom-chat-widget skill instead.
version: 1.1.0
author: Marc
applyTo: "powerpages.config.json,**/powerpages.config.json"
tags:
  - power-pages
  - chat-widget
  - csp
  - content-security-policy
  - self-hosting
  - web-files
  - code-sites
  - third-party-scripts
---

# Embedding Third-Party Widgets on Power Pages Code Sites

> **Trigger**: "embed widget", "chat widget CSP", "external script blocked",
> "Content Security Policy violation", "self-host script", "third-party JS",
> "widget not loading", "script-src violation", "chat bubble", "D365 modern chat"

Safely embed any external JavaScript widget on Power Pages Code Sites (v2)
without modifying CSP or risking site breakage.

---

## Golden Rule

**NEVER modify CSP on Power Pages Code Sites.** Instead, self-host all external
scripts and assets as Power Pages web files (served from `'self'`).

---

## ⚠️ Exception — D365 Omnichannel live chat widget (DON'T self-host it)

Self-hosting works for *most* external widgets, but **NOT** for the Dynamics 365
Omnichannel Live Chat Widget (the `oc-cdn…/LiveChatBootstrapper.js` script).
Even if you self-host the bootstrapper, at runtime it loads **further script
chunks from `oc-cdn`** which the code-site `script-src` still blocks — so the
chat never loads. Self-hosting is a dead end here.

**Instead, use the [`omnichannel-custom-chat-widget`](../omnichannel-custom-chat-widget/SKILL.md)
skill:** bundle `@microsoft/omnichannel-chat-sdk` (runs from `'self'`, allowed by
`script-src`) behind a custom React UI. The code-site CSP sets only `script-src`
and `style-src` — there is **no `connect-src`/`default-src`** — so the SDK's
runtime WebSocket/fetch to `*.omnichannelengagementhub.com` is unrestricted and
the bundled SDK just works.

| Task | Skill |
|---|---|
| Analytics tag, generic chat bubble, arbitrary third-party JS | **this skill** (self-host) |
| D365 Omnichannel live chat | **omnichannel-custom-chat-widget** (bundled SDK) |

---

## Why Self-Hosting Is Required

Power Pages Code Sites enforce a strict, platform-managed Content Security
Policy (CSP). There are three ways to try adding external domains to CSP — 
**all three are dangerous or broken**:

| Approach | Result |
|---|---|
| `HTTP/Content-Security-Policy` site setting | **REPLACES** the entire platform CSP. Breaks `'self'`, inline scripts, platform CDN. **Site goes down.** |
| Design Studio → Security → Advanced → CSP | Creates the same dangerous site setting above. Same result. |
| `HTTP/Content-Security-Policy/script-src` (per-directive) | **Ignored** on Code Sites v2 — only works on traditional portals. |

**The only safe approach is self-hosting.** Download external scripts and images
into `public/` so Vite copies them to `dist/`, and PAC CLI uploads them as
Power Pages web files served from the site's own domain.

---

## Step-by-Step Implementation

### Step 1 — Download External Assets

```powershell
# Create public/ directory if it doesn't exist
New-Item -ItemType Directory -Path "public" -Force

# Download the widget script
Invoke-WebRequest -Uri "https://example.com/widget.js" -OutFile "public/widget.js"

# Download any images/assets the widget references
Invoke-WebRequest -Uri "https://example.com/icon.png" -OutFile "public/icon.png"
```

Vite automatically copies `public/` contents to `dist/` during build. PAC CLI
then uploads `dist/` files as Power Pages web files.

### Step 2 — React Component for SPA Pages

Create a React component that loads the widget script dynamically:

```tsx
// src/components/ChatWidget.tsx
import { useEffect } from "react";

declare global {
  interface Window {
    WidgetConfig?: Record<string, unknown>;
  }
}

const WIDGET_CONFIG = {
  // ... your widget configuration
  // Use self-hosted paths for any image URLs:
  avatar: "/icon.png",  // NOT https://external-domain.com/icon.png
};

export default function ChatWidget() {
  useEffect(() => {
    if (window.WidgetConfig) return;
    window.WidgetConfig = WIDGET_CONFIG;

    const script = document.createElement("script");
    script.src = "/widget.js";  // Self-hosted — no CSP issues
    script.async = true;
    document.head.appendChild(script);
  }, []);

  return null;
}
```

Add it to `App.tsx` after Footer:

```tsx
import ChatWidget from "./components/ChatWidget";

// Inside AppRoutes return:
<>
  <Header />
  <main>...</main>
  <Footer />
  <ChatWidget />
</>
```

### Step 3 — Server-Rendered Pages (Profile, Search, etc.)

SPA pages use the React component. Server-rendered pages (Profile.aspx,
Search.aspx, etc.) need the widget injected via web templates.

**Problem**: `pac pages upload-code-site` OVERWRITES Header and Footer web
templates to `<div/>` on every deploy.

**Solution**: Create a `post-deploy-patch.ps1` script that patches the
templates via Dataverse API AFTER each deploy.

```powershell
# post-deploy-patch.ps1
$footerSource = @'
<div/>
<script>
if(!window.WidgetConfig){
  window.WidgetConfig = { /* config with self-hosted paths */ };
  (function(){
    var s = document.createElement('script');
    s.src = '/widget.js';
    document.head.appendChild(s);
  })();
}
</script>
'@

# Patch via Dataverse API
$record = Invoke-RestMethod -Uri "$envUrl/api/data/v9.2/powerpagecomponents($footerId)?$select=content" -Headers $headers
$content = $record.content | ConvertFrom-Json
$content.source = $footerSource
$body = @{ content = ($content | ConvertTo-Json -Compress -Depth 5) } | ConvertTo-Json -Depth 5
Invoke-RestMethod -Uri "$envUrl/api/data/v9.2/powerpagecomponents($footerId)" -Headers $headers -Method Patch -Body ([System.Text.Encoding]::UTF8.GetBytes($body))
```

### Step 4 — Integrate Into Deploy Pipeline

Add post-deploy-patch.ps1 to your `deploy-update.ps1`:

```powershell
# After pac pages upload-code-site completes:
# Gate 7: Post-deploy patch
$patchScript = Join-Path $PSScriptRoot "post-deploy-patch.ps1"
if (Test-Path $patchScript) { & $patchScript }
```

### Step 5 — Boot Error Handler

The SPA boot diagnostics handler may show "Failed to load" if ANY script fails.
Exclude non-essential widget scripts:

```javascript
window.addEventListener('error', function (e) {
  if (e.target && (e.target.tagName === 'SCRIPT' || e.target.tagName === 'LINK')) {
    var url = e.target.src || e.target.href || '';
    // Ignore non-essential scripts
    if (url.indexOf('widget') !== -1) {
      console.warn('[BOOT] Non-essential resource failed (ignored):', url);
      return;
    }
    // Show error only for essential resources
    showBootError('Failed to load: ' + url);
  }
}, true);
```

---

## Key Architecture Decisions

| Decision | Rationale |
|---|---|
| Self-host in `public/` | Vite copies to `dist/`, PAC uploads as web files, served from `'self'` |
| React component for SPA | Guaranteed script execution via `useEffect`, no CSP issues |
| Footer template for server pages | Header/Footer render on all pages with `usewebsiteheaderandfooter: true` |
| Post-deploy API patch | PAC CLI overwrites Header/Footer — must re-inject after every deploy |
| Guard `if(!window.Config)` | Prevents double-loading when both SPA component and template inject |

---

## What NOT To Do

1. **DO NOT** add `<script>` tags to `index.html` — Power Pages strips them from `adx_copy`
2. **DO NOT** set `HTTP/Content-Security-Policy` site settings — REPLACES entire platform CSP
3. **DO NOT** use Design Studio CSP UI — creates the same dangerous site setting
4. **DO NOT** use `HTTP/Content-Security-Policy/script-src` — ignored on Code Sites v2
5. **DO NOT** reference external domains in widget config (images, scripts) — use self-hosted paths
6. **DO NOT** try/catch `VoiceVideoCallingLoadFailed` — the rejection is uncatchable from minified SDK code. Gut the function body instead.

---

## Cascading Dependencies (CRITICAL)

Widget scripts often dynamically load sub-dependencies from CDNs at runtime.
These are ALSO blocked by CSP and must ALSO be self-hosted.

### D365 Modern Chat Widget dependency chain:
```
widget-core.js (self-hosted, 146KB)
  ├── adaptivecards.min.js (self-hosted, 442KB) — renders adaptive cards
  ├── chat-sdk-bundle.js (self-hosted, 1.3MB) — Omnichannel Chat SDK
  │     └── CallingBundle.js (Azure CDN, BLOCKED) — voice/video calling
  └── avatar images (self-hosted PNGs)
```

### How to patch:
1. Download `widget-core.js` to `public/`
2. Open it and find CDN URL arrays (search for `acSources` and `sdkSources`)
3. Replace with local paths: `['/adaptivecards.min.js']` and `['/chat-sdk-bundle.js']`
4. Gut `preloadVoiceVideoCallingSDK` function body — it loads `CallingBundle.js` from Azure CDN which CSP blocks, and the error is uncatchable

---

## Pre-filling Form Fields for Logged-In Users

### Problem:
Power Pages `Microsoft.Dynamic365.Portal.User` loads AFTER React mounts.

### Solution — Two-source approach:
```tsx
// ChatWidget.tsx — reads at mount time (may miss if user loads late)
const user = getPortalUser();
if (user) {
  config.defaultName = `${user.firstName} ${user.lastName}`.trim();
  config.defaultEmail = user.emailAddress || user.userName;
}
```

```javascript
// widget-core.js — reads on launcher click (guaranteed to have user by then)
function prefillPrechatForm() {
  var defName = config.defaultName, defEmail = config.defaultEmail;
  if (!defName || !defEmail) {
    var pu = window.Microsoft?.Dynamic365?.Portal?.User;
    if (pu?.userName) {
      defName = defName || (pu.firstName + ' ' + pu.lastName).trim();
      defEmail = defEmail || pu.emailAddress || pu.userName;
    }
  }
  if (defName) document.getElementById('d365Name').value = defName;
  if (defEmail) document.getElementById('d365Email').value = defEmail;
}
// Call on: launcher.onclick AND showView('prechat')
```

### Important: `email` vs `userName` vs `emailAddress`
- `userName` is a short login alias — NOT the full email
- **`email`** is the correct field for the full email address
- There is NO `emailAddress` field — that was wrong
- Always use: `pu.email || pu.emailAddress || pu.userName`

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| "violates Content Security Policy directive" | External domain not in CSP | Self-host the script in `public/` |
| Site completely broken after CSP change | `HTTP/Content-Security-Policy` replaced platform CSP | DELETE the site setting + restart |
| Widget loads on SPA but not Profile page | Footer template overwritten by PAC CLI | Run `post-deploy-patch.ps1` |
| "Failed to load ProjectA" error on startup | Boot error handler caught widget script | Add widget URL to exclusion list |
| Widget loads but no chat bubble appears | Widget config wrong or Omnichannel not configured | Check widgetId and orgUrl |
| "Connecting you with an agent" stuck forever | `VoiceVideoCallingLoadFailed` crashes `initChat` | Gut `preloadVoiceVideoCallingSDK` function body |
| Chat SDK loads but CallingBundle.js blocked | Azure CDN blocked by platform CSP | Disable VoiceVideo — can't self-host (URL is dynamic inside minified SDK) |
| Pre-chat name/email not filling | Portal user not loaded at mount time | Add `prefillPrechatForm()` on launcher click |
| Email shows alias not full address | Using `userName` instead of `emailAddress` | Use `pu.emailAddress \|\| pu.userName` |
| favicon.ico 404 | No proper ICO file in `public/` | Create real ICO with embedded 16+32px PNGs |

---

## File Structure

```
project/
├── public/
│   ├── widget.js          # Self-hosted widget script
│   ├── icon.png           # Self-hosted avatar/icon images
│   └── ...
├── src/
│   └── components/
│       └── ChatWidget.tsx  # React wrapper component
├── scripts/
│   ├── deploy-update.ps1  # Calls post-deploy-patch after upload
│   └── post-deploy-patch.ps1  # Patches Header/Footer via API
└── .powerpages-site/
    └── web-templates/
        ├── header/         # Overwritten by PAC — patched via API
        └── footer/         # Overwritten by PAC — patched via API
```
