---
name: power-pages-upload
description: >
  Use when the user asks to "redeploy", "upload changes", "push updates",
  "update the site", "sync changes", "safe update", or "safe update and restart".
  Performs a safe incremental upload of changes to an already-deployed Power Pages
  Code Site, with pre-flight verification, build, upload, and restart.
version: 2.0.0
author: Marc
applyTo: "powerpages.config.json,**/powerpages.config.json"
tags:
  - power-pages
  - upload
  - redeploy
  - pac-cli
  - incremental
  - safe-update
  - restart
---

# Safe Update & Restart — Power Pages Code Site

> **Trigger**: "Safe update and restart", "Redeploy the site", "Push my changes"

Perform a safe incremental upload of changes to an already-deployed Power Pages
Code Site. This is the ONLY workflow for updating existing sites.

## Portal Lookup Table

Look up the correct IDs from `.github/copilot-instructions.md` or use these:

| Project | Dataverse Site ID | Admin API Site ID |
|---|---|---|
| `ProjectB/SSENTPortal/` | `143708f4-13d7-4de3-8235-67b31ae1844e` | (resolve by name) |
| `ProjectC/` | `e84ce96b-5a6d-4841-abad-0c3bfbf619a4` | `67685b8f-7b26-460a-a4bc-109911c133e3` |
| `ProjectA/` | `0e6137ee-23eb-4bdb-b802-bb37e03b55c9` | `cbb41d78-71c5-4a02-9a39-5e32e4643b2f` |

**Shared Environment ID**: `08690526-047d-ed9d-ab35-4528a98c0f4f`

## Prerequisites

- Site already deployed at least once (see deploy skill).
- PAC CLI authenticated (`pac auth who`).
- Changes built (`npm run build`).

## Critical Safety Rules

1. **NEVER delete `.powerpages-site/`** — PAC creates a NEW site record if missing.
2. **NEVER delete `powerpagesites` records via API** — platform protection keeps them alive.
3. **Always verify `website.yml` ID** matches the Admin API `websiteRecordId`.
4. **Always build before deploy** — source files are NOT uploaded, only build output.
5. **Always use `--compiledPath ./dist`** — omitting it uploads source instead of build.
6. **Always restart** after deploying permissions, site settings, or code changes.
7. **`PowerPageComponentDeletePlugin` errors are benign** — upload still succeeds.

## Step-by-Step Procedure

### Phase 1: Build

```powershell
cd <project-root>   # e.g. ProjectA/, ProjectC/, ProjectB/SSENTPortal/
npm run build
```

Verify build succeeds with no TypeScript errors.

### Phase 2: Deploy

```powershell
pac pages upload-code-site --rootPath . --compiledPath ./dist
```

> **Note**: If using Create React App, change `--compiledPath` to `"./build"`.
> If upload fails with a transient error, retry once — PAC CLI SSE connections
> occasionally drop.

### Phase 3: Restart

Restart the site using the Power Platform Admin REST API. Substitute the
correct `$envId` and `$siteId` from the portal lookup table above.

```powershell
$token = az account get-access-token --resource "https://api.powerplatform.com" --query accessToken -o tsv
$headers = @{ "Authorization" = "Bearer $token"; "Content-Type" = "application/json" }
$envId = "08690526-047d-ed9d-ab35-4528a98c0f4f"
$siteId = "<Admin API Site ID from lookup table>"
Invoke-RestMethod -Uri "https://api.powerplatform.com/powerpages/environments/$envId/websites/$siteId/restart?api-version=2022-03-01-preview" -Headers $headers -Method Post
```

> **No `pac pages restart` exists** — the Admin REST API is the only way.
> OAuth resource is `https://api.powerplatform.com` (NOT the org URL).

### Phase 4: Verify

1. Open the site URL in the browser.
2. Hard refresh (`Ctrl+Shift+R`).
3. Verify changes are visible.
4. Check browser console for errors.

## Vite Cache Busting Config

To ensure unique file names on each build (eliminates CDN cache issues):

```typescript
// vite.config.ts
export default defineConfig({
  build: {
    rollupOptions: {
      output: {
        entryFileNames: 'assets/[name]-[hash].js',
        chunkFileNames: 'assets/[name]-[hash].js',
        assetFileNames: 'assets/[name]-[hash].[ext]',
      },
    },
  },
});
```

## Common Mistakes & Warnings

- **Always build before uploading** -- Source files are not uploaded, only the
  build output.
- **CDN cache** -- Changes may not appear immediately. Hard refresh or wait.
- **Same command for first deploy and updates** -- `pac pages upload-code-site`
  handles both cases.
- **Check for build errors** -- If `npm run build` has warnings or errors,
  fix them before uploading.
- **No partial upload** -- The entire build is uploaded each time. There's no
  diff-based incremental upload.
- **`--compiledPath` is required (PAC CLI v2.1.2+)** -- Omitting it produces:
  `"The value passed to '--compiledPath' is invalid. A required argument
  --compiledPath is missing."` Always pass `--compiledPath "./dist"` (Vite)
  or `--compiledPath "./build"` (CRA).

## CRITICAL — Safe Update Rules

These rules MUST be followed for every update. Violating them causes orphaned
records, duplicate sites, or broken deployments.

1. **NEVER delete `.powerpages-site/`** — PAC creates a NEW site record if it's missing.
2. **NEVER delete `powerpagesites` records via API** — they don't actually delete
   (platform protection). Components cascade-delete but the site record survives,
   leaving an empty shell the runtime still points to.
3. **Always verify `website.yml` ID** matches the Admin API `websiteRecordId`
   before deploying. Check with:
   ```powershell
   GET https://api.powerplatform.com/powerpages/environments/{envId}/websites
   # → websiteRecordId must match .powerpages-site/website.yml id
   ```
4. **Always build before deploy** — `npm run build && pac pages upload-code-site`
5. **Always restart** after deploying permissions or site setting changes.
6. **Use `scripts/deploy-update.ps1`** for safe deploys — it has gate checks.
7. **`PowerPageComponentDeletePlugin` errors are benign** — they occur when PAC
   cleans up old hashed bundle files. Upload still succeeds.
8. **Web file content uses `filecontent` column** (file type on powerpagecomponent),
   NOT annotation records. The YAML `annotationid` fields are legacy.
9. **Auth providers survive site rebuilds** — `AzureAd, LocalAuthentication` are
   stored at the Admin API runtime level, not in powerpagecomponents.
10. **Auth site settings (28 of them)** are auto-created by the runtime on first
    site provisioning. No need to manually create auth settings.
