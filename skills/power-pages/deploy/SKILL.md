---
name: power-pages-deploy
description: >
  Use when the user asks to "deploy the site", "upload the site", "publish to Power Pages",
  "first deploy", or "go live". Performs the initial deployment of a Power Pages
  Code Site using pac pages upload-code-site.
version: 1.0.0
author: Marc
applyTo: "powerpages.config.json,**/powerpages.config.json"
tags:
  - power-pages
  - deploy
  - pac-cli
  - upload
---

# Deploy a Power Pages Code Site (First Time)

> **Trigger**: "Deploy the site to Power Pages"

Perform the initial deployment of a Power Pages Code Site. This creates the
`powerpagesite` record in Dataverse and uploads all static assets.

## Prerequisites

- PAC CLI authenticated (`pac auth who`).
- Project built (`npm run build` output exists in `dist/` or `build/`).
- `powerpages.config.json` in the project root.

## Before You Start

1. Use the **Microsoft Learn MCP** to check for any recent changes to the
   `pac pages upload-code-site` command syntax.
2. Verify the build output directory exists.

## Step-by-Step Procedure

### Phase 1: Pre-Flight Checks

```powershell
# Verify PAC CLI auth
pac auth who

# Verify the build exists
$buildDir = if (Test-Path "dist") { "dist" } elseif (Test-Path "build") { "build" } else { $null }
if (-not $buildDir) {
  Write-Error "No build directory found. Run 'npm run build' first."
  return
}

# Verify powerpages.config.json exists
if (-not (Test-Path "powerpages.config.json")) {
  Write-Error "powerpages.config.json not found in project root."
  return
}
```

### Phase 2: Build the Project

```powershell
npm run build
```

Verify the build completed without errors.

### Phase 3: Check for JavaScript Blocking

Some Power Platform environments block `.js` file uploads. Check and resolve:

```powershell
# Check if JS files are blocked
pac env list-settings --filter "BlockJavaScriptFiles"

# If blocked, update the setting
pac env update-settings --name "BlockJavaScriptFiles" --value "No"
```

### Phase 4: Deploy

```powershell
# Upload the code site (--compiledPath is REQUIRED as of PAC CLI v2.1.2+)
pac pages upload-code-site --rootPath "." --compiledPath "./dist"
```

> **Note**: If the project uses Create React App, change `--compiledPath` to
> `"./build"`. The pre-flight check in Phase 1 detects which directory exists.

This command:
1. Reads `powerpages.config.json` for site name and slug.
2. Creates the `powerpagesite` record if it doesn't exist.
3. Uploads all files from the build output.
4. Makes the site available at `https://<site-slug>.powerappsportals.com`.

### Phase 5: Verify Deployment

1. Get the site URL from the command output.
2. Open the URL in a browser.
3. Verify the site loads correctly.
4. Check browser DevTools console for errors.

### Phase 6: Post-Deployment

After first deploy, suggest next steps:
- Set up authentication (setup-auth skill)
- Configure Web API access (setup-permissions skill)
- Add sample data (add-sample-data skill)

> **If auth, security, or site settings were changed**: Follow up with the
> **restart-site** skill to restart the site via the Admin REST API. A deploy
> alone does not restart the runtime — new site settings and table permissions
> are only picked up after a restart.

### Phase 7: Public Visibility (Non-Production Environments)

If the site is on a **trial or developer environment** and the user wants it reachable anonymously over the internet, the maker portal's **Public** toggle is blocked by default tenant governance — the fix is a tenant-admin toggle, NOT "convert trial to production".

1. https://admin.powerplatform.microsoft.com/ → **Manage** → **Power Pages** → **Governance controls**
2. Dropdown → **"Set site visibility to public access for non-production sites"**
3. Pick the environment → change **None** → **All** (or **Specific sites** and pick just this site) → **Save**
4. Maker portal → site → **Security** → **Site visibility** → **Public** → **Save**

Docs: https://learn.microsoft.com/power-pages/admin/site-visibility-governance (GA Mar 20, 2026 — default policy is `None`, so this step is required on every fresh tenant).

## Common Mistakes & Warnings

- **Build before deploying** -- `pac pages upload-code-site` uploads the built
  files, not the source. Always `npm run build` first.
- **JavaScript blocking** -- If the site loads but shows a blank page, check if
  `.js` files are being blocked by the environment.
- **Use `pac pages upload-code-site`** -- NOT `pac paportal upload`. The latter
  is for traditional portals only.

### CRITICAL: Dual Site ID Trap

When you deploy with `pac pages upload-code-site` and then activate/convert the
site in Design Studio, **two `powerpagesites` records** are created:

| Record | Created By | Purpose |
|--------|-----------|---------|
| PAC CLI site | `pac pages upload-code-site` | Where PAC uploads JS/CSS/templates |
| Runtime site | Design Studio activation | Where the browser serves from |

**These are completely independent.** Code goes to one, the browser serves from
the other. Code changes will never appear in the browser.

#### How to Detect
```powershell
$sites = (Invoke-RestMethod -Uri "$envUrl/api/data/v9.2/powerpagesites?`$filter=contains(name,'YOUR_SITE')&`$select=powerpagesiteid,name" -Headers $h).value
# If more than 1 result → you have the dual site problem
```

#### How to Fix
1. Identify the **runtime** site ID (the one with auth settings):
   ```powershell
   foreach ($s in $sites) {
     $id = $s.powerpagesiteid
     $count = (Invoke-RestMethod -Uri "$envUrl/api/data/v9.2/powerpagecomponents?`$filter=powerpagecomponenttype eq 9 and _powerpagesiteid_value eq $id and startswith(name,'Authentication/')&`$select=powerpagecomponentid" -Headers $h).value.Count
     Write-Host "$id => $count auth settings"
   }
   ```
2. **Delete** the extra (non-runtime) site records.
3. Get the runtime site's template IDs:
   ```powershell
   $templates = (Invoke-RestMethod -Uri "$envUrl/api/data/v9.2/powerpagecomponents?`$filter=powerpagecomponenttype eq 8 and _powerpagesiteid_value eq $runtimeId and (name eq 'Header' or name eq 'Footer')&`$select=powerpagecomponentid,name" -Headers $h).value
   $lang = (Invoke-RestMethod -Uri "$envUrl/api/data/v9.2/powerpagesitelanguages?`$filter=_powerpagesiteid_value eq $runtimeId&`$select=powerpagesitelanguageid" -Headers $h).value[0]
   ```
4. **Update** `.powerpages-site/website.yml` with the runtime site ID + template IDs.
5. Redeploy — `pac pages upload-code-site` now targets the live site.

#### Prevention
- **NEVER delete `.powerpages-site/`** — PAC CLI creates a NEW site record each time.
- After first deploy + Design Studio activation, immediately check for duplicates
  and fix `website.yml` before any further deploys.

### Home Page Structure (Non-Root Copy = SPA Shell)

Code Sites have TWO Home page records (`powerpagecomponenttype=2, name='Home'`):
- **Root** (isroot=True): generic layout div (ignored for SPAs)
- **Non-root** (isroot=False): contains the FULL `dist/index.html` as its `copy` field

The non-root copy MUST contain `<div id="root">`, `<script src="./assets/index.js">`,
and `<link href="./assets/index.css">`. If this is corrupted (e.g., by manually
patching the `copy` field), the SPA won't load.

### Web File Parent Pages (assets/ Path)

Built JS/CSS files (`index.js`, `index.css`) are stored as web files (type 3)
under a parent page called `assets` (partialurl: `assets`). This makes them
accessible at `/assets/index.js` and `/assets/index.css`, matching the
`<script src="./assets/index.js">` reference in the Home page.

If the `assets` parent page is deleted or the web file's `parentpageid`
references a non-existent page, the JS/CSS will 404:
- The site shows a blue/styled page (CSS still from inline or cached) but
  React never mounts (no `<div id="root">` content)
- Console shows `[ZAVA-AUTH]` logs but never `[ZAVA] main.tsx loaded`

### Always Add a React Error Boundary

Without an error boundary, any React crash = blank white screen with zero diagnostics.
Add this to `main.tsx`:

```tsx
class ErrorBoundary extends Component<{children: ReactNode}, {hasError: boolean; error: Error | null}> {
  constructor(props) { super(props); this.state = { hasError: false, error: null }; }
  static getDerivedStateFromError(error) { return { hasError: true, error }; }
  componentDidCatch(error, info) { console.error("[APP] React crashed:", error, info.componentStack); }
  render() {
    if (this.state.hasError) return <div style={{padding:"2rem"}}><h1>Something went wrong</h1><pre>{this.state.error?.message}</pre></div>;
    return this.props.children;
  }
}
// Wrap App:
<ErrorBoundary><App /></ErrorBoundary>
```
- **HTML manifest error** -- If you see "manifest.json 404" in the console,
  ensure the `index.html` references the correct base path.
- **No `pac pages restart`** -- There is no CLI command to restart a Power Pages
  site. Use the **restart-site** skill, which calls the Power Platform Admin
  REST API programmatically.
- **YAML files overwrite Dataverse** -- `pac pages upload-code-site` deploys
  YAML files from `.powerpages-site/` and overwrites matching Dataverse records.
  If you changed a site setting via the API, ensure the local YAML file matches
  or your change will be reverted on next deploy. See the
  **code-sites-v2-reference** skill for details.
- **Site slug must be unique** -- The slug becomes part of the URL. If it
  conflicts with another site, the deploy will fail.
- **`--compiledPath` is required (PAC CLI v2.1.2+)** -- Omitting it produces:
  `"The value passed to '--compiledPath' is invalid. A required argument
  --compiledPath is missing."` Always pass `--compiledPath "./dist"` (Vite)
  or `--compiledPath "./build"` (CRA).

## Related Skills

| Skill | When to Use |
|---|---|
| [restart-site](../restart-site/SKILL.md) | Restart after auth/security/settings changes |
| [upload](../upload/SKILL.md) | Incremental redeployment (not first time) |
| [code-sites-v2-reference](../code-sites-v2-reference/SKILL.md) | v2 data model, YAML overwrite behaviour |
