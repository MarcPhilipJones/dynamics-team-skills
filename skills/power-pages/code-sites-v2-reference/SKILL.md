---
name: power-pages-code-sites-v2-reference
description: >
  Reference skill for Power Pages Code Sites v2 data model. Use when you need
  to understand the difference between Code Sites and traditional portals,
  look up powerpagecomponent type codes, or check YAML deployment behaviour.
  This is a lookup reference, not a step-by-step workflow.
version: 1.0.0
author: Marc
applyTo: "powerpages.config.json,**/powerpages.config.json"
tags:
  - power-pages
  - code-sites
  - v2-data-model
  - reference
---

# Power Pages Code Sites v2 — Reference Guide

> **Trigger**: "What's the difference between Code Sites and portals?",
> "What component type is a site setting?", "Why did pac paportal fail?"

This is a **reference skill** — consult it when building or debugging Code Sites.

## Code Sites vs Traditional Portals

| Aspect | Code Sites (v2) | Traditional Portals |
|---|---|---|
| Data record | `powerpagesite` | `adx_website` |
| Upload command | `pac pages upload-code-site` | `pac paportal upload` |
| Download command | `pac pages download-code-site` | `pac paportal download` |
| Site settings table | `powerpagecomponent` (type 9) | `adx_sitesettings` |
| Table permissions table | `powerpagecomponent` (type 18) | `adx_entitypermission` |
| Web templates table | `powerpagecomponent` (type 8) | `adx_webtemplate` |
| Config file | `powerpages.config.json` | `website.yml` |
| Framework support | React, Vue, Angular, Astro (SPA) | Liquid templates |
| `pac paportal list` | Lists both types | Lists both types |

**Key rule**: If your project has `powerpages.config.json`, it's a Code Site.
Use `pac pages` commands, not `pac paportal`.

## PAC CLI Commands

| Command | Works For | Notes |
|---|---|---|
| `pac pages upload-code-site` | Code Sites only | Requires `--compiledPath` (PAC CLI v2.1.2+) |
| `pac pages download-code-site` | Code Sites only | Downloads source to local folder |
| `pac paportal upload` | Traditional portals only | Errors on Code Sites ("Website record doesn't exist") |
| `pac paportal download` | Traditional portals only | Errors on Code Sites |
| `pac paportal list` | Both | Lists all sites regardless of type |

## powerpagecomponent Type Reference

All Code Site v2 configuration is stored as `powerpagecomponent` records in
Dataverse. The `powerpagecomponenttype` field determines the record type:

| Type Code | Component Type | Notes |
|---|---|---|
| 1 | Publishing State | Draft, Published, etc. |
| 2 | Web Page | Page record |
| 3 | Web File | Static file |
| 4 | Page Template Variant | |
| 5 | Web Page Variant | |
| 6 | Page Template | |
| 7 | Content Snippet | Reusable text/HTML fragments |
| 8 | Web Template | Liquid templates |
| 9 | **Site Setting** | `Webapi/*` settings, auth config, etc. |
| 10 | Web Page Access Rule | |
| 11 | **Web Role** | Anonymous, Authenticated, Custom |
| 12 | Website Access Permission | |
| 13 | Page Redirect | |
| 18 | **Table Permission** | Entity-level CRUD permissions |

### Querying Components by Type

```powershell
# Get all site settings (type 9) for a specific site
$settings = Invoke-RestMethod `
  -Uri "$envUrl/api/data/v9.2/powerpagecomponents?`$filter=powerpagecomponenttype eq 9 and _powerpagesiteid_value eq '$siteId'&`$select=name,content" `
  -Headers $headers
$settings.value | ForEach-Object { [PSCustomObject]@{ Name = $_.name; Content = $_.content } }
```

## YAML Overwrite Behaviour — Critical Warning

> **This is the single most common operational trap with Code Sites.**

When you run `pac pages upload-code-site`, it deploys YAML files from your
local `.powerpages-site/` folder to Dataverse. This **overwrites** Dataverse
records with matching IDs.

### What This Means

1. You create a site setting via the Dataverse API (e.g., `Webapi/incident/enabled = true`).
2. The setting works correctly in the portal.
3. You redeploy with `pac pages upload-code-site`.
4. If `.powerpages-site/site-settings/` contains a YAML file for the same
   setting with a **different value**, the YAML value overwrites your API change.
5. The setting reverts and things break.

### How to Avoid This

- **Always check the YAML files** in `.powerpages-site/site-settings/` after
  creating settings via the API.
- **Fix YAML source files** when correcting site settings — fixing only
  Dataverse is futile because the next deploy overwrites it.
- After creating settings via API, download the site to sync YAML:
  ```powershell
  pac pages download-code-site --rootPath "."
  ```
- Treat YAML files as the **source of truth** for settings, not Dataverse.

### YAML File Format

Site settings YAML files live in `.powerpages-site/site-settings/` and follow
this naming convention: `<name>.sitesetting.yml`.

## Site Settings Storage

Site settings for Code Sites are stored as `powerpagecomponent` records:

| Field | Value |
|---|---|
| `powerpagecomponenttype` | `9` |
| `name` | Setting name (e.g., `Webapi/incident/enabled`) |
| `content` | JSON string: `{"value":"true","websiteid":"<site-guid>"}` |
| `_powerpagesiteid_value` | The site's `powerpagesiteid` GUID |

They are **NOT** stored in the `adx_sitesettings` table. Querying
`adx_sitesettings` for Code Site settings will return nothing.

## Anti-Forgery Token in Code Sites

Code Sites do **not** inject a `<meta name="__RequestVerificationToken">` tag
into the page HTML (traditional portals do). Instead, fetch the token from:

```
GET /_layout/tokenhtml
```

This returns HTML containing a hidden input with the token value. Parse it:

```typescript
const response = await fetch('/_layout/tokenhtml');
const html = await response.text();
const match = html.match(/value="([^"]+)"/);
const token = match ? match[1] : '';
```

Cache this token (it's session-scoped) and auto-retry on 403 by clearing the
cache and re-fetching. See the **setup-webapi** skill for full implementation.

## Related Skills

| Skill | When to Use |
|---|---|
| [deploy](../deploy/SKILL.md) | First-time deployment |
| [upload](../upload/SKILL.md) | Incremental redeployment |
| [restart-site](../restart-site/SKILL.md) | Restart after auth/security/settings changes |
| [setup-permissions](../setup-permissions/SKILL.md) | Create site settings + table permissions |
| [setup-webapi](../setup-webapi/SKILL.md) | TypeScript API client with token handling |

---

## Dual Site ID Trap — Critical Architecture Warning

### The Problem

`pac pages upload-code-site` creates a `powerpagesites` record when first
deploying. When you then activate/convert the site in Design Studio (or it
was created there first), a **second** `powerpagesites` record is created.

| Record | Created By | What PAC CLI Does | What Browser Serves |
|--------|-----------|-------------------|---------------------|
| PAC CLI site | `pac pages upload-code-site` | Uploads JS/CSS/templates here | **Nothing** |
| Runtime site | Design Studio | Ignored by PAC CLI | **Serves from here** |

**Result**: Code changes deployed via PAC never reach the browser. The
browser serves stale code from the runtime site.

### How to Detect

```powershell
$sites = (Invoke-RestMethod -Uri "$envUrl/api/data/v9.2/powerpagesites?`$filter=contains(name,'SITE_NAME')&`$select=powerpagesiteid,name" -Headers $headers).value
# Multiple results = dual site ID problem
```

Alternatively check the Admin API:
```powershell
# The websiteRecordId is the RUNTIME site
$adminSite = Invoke-RestMethod -Uri "https://api.powerplatform.com/powerpages/environments/$envId/websites?api-version=2022-03-01-preview" -Headers $ppHeaders
$adminSite.value | Where-Object { $_.name -eq 'SITE_NAME' } | Select-Object name, id, websiteRecordId
# websiteRecordId = runtime powerpagesiteid (may differ from website.yml id)
```

### How to Fix (Proven Working — ProjectA, March 2026)

1. **Find runtime ID**: Query auth settings — the `_powerpagesiteid_value` on
   `Authentication/*` settings is the runtime ID.
2. **Delete extras**: Delete all non-runtime `powerpagesites` records via API.
3. **Get template IDs** for the runtime site:
   ```powershell
   # Header + Footer (type 8)
   $templates = (Invoke-RestMethod -Uri "$envUrl/api/data/v9.2/powerpagecomponents?`$filter=powerpagecomponenttype eq 8 and _powerpagesiteid_value eq $runtimeId and (name eq 'Header' or name eq 'Footer')&`$select=powerpagecomponentid,name" -Headers $h).value
   # Language
   $lang = (Invoke-RestMethod -Uri "$envUrl/api/data/v9.2/powerpagesitelanguages?`$filter=_powerpagesiteid_value eq $runtimeId&`$select=powerpagesitelanguageid" -Headers $h).value[0]
   ```
4. **Rewrite `website.yml`**:
   ```yaml
   defaultlanguage: <language-id>
   footerwebtemplateid: <footer-template-id>
   headerwebtemplateid: <header-template-id>
   id: <runtime-site-id>
   name: <site-name>
   website_language: 1033
   ```
5. **Redeploy**: `pac pages upload-code-site` now targets the live site.
6. **Restart**: Use the Admin REST API.

### Prevention Rules

- **NEVER delete `.powerpages-site/`** — PAC CLI creates a NEW site record
  each time, making the problem worse.
- After first deploy + Design Studio activation, **immediately check for
  duplicate `powerpagesites` records** and fix `website.yml`.
- ProjectB works because it has **one** site record (143708f4). ProjectA broke
  because it had three (created by repeated `.powerpages-site` deletions).

---

## Code Site SPA Architecture — How It Actually Works

### Home Page Structure

Code Sites have **two** Home page records (`powerpagecomponenttype=2, name='Home'`):

| Record | `isroot` | `copy` Contains | Purpose |
|--------|----------|-----------------|---------|
| Root page | `True` | Generic layout div | Ignored for SPAs |
| Non-root page | `False` | Full `dist/index.html` | **SPA shell** — the one that matters |

The **non-root** Home page's `copy` field IS the complete HTML document served
to the browser: `<!doctype html>`, `<div id="root">`, `<script>` tags, etc.

### Web File Serving (assets/ path)

Built JS/CSS files are served via web files (type 3) under a parent page:

```
/ (Home page)
└── /assets/ (Web Page, partialurl: "assets")
    ├── index.js (Web File, partialurl: "index.js")  → /assets/index.js
    └── index.css (Web File, partialurl: "index.css") → /assets/index.css
```

Each web file's `filecontent` field contains a GUID reference pointing to the
compiled artifact binary (stored internally by PAC CLI). If this GUID is empty
or references a deleted record, the file 404s.

### Debugging Checklist: "Blue/blank page, no React"

If the site shows a colored background but React doesn't mount:

1. **Check console for `[APP] main.tsx loaded`** — if missing, JS isn't loading
2. **Check Network tab** for `assets/index.js` — is it 200 or 404?
3. **Check `powerpagesites` count** — dual site ID?
4. **Check `website.yml` ID** — matches the runtime site?
5. **Check web file parent page** — `index.js.content.parentpageid` exists and
   is on the runtime site?
6. **Check `filecontent` GUID** — non-empty and references a valid artifact?
