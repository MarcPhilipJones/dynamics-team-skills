---
name: power-pages-restart-site
description: >
  Use when the user asks to "restart the site", "restart Power Pages",
  "clear site cache", "site not picking up changes", or "refresh the portal".
  Restarts a Power Pages Code Site programmatically via the Power Platform
  Admin REST API.
version: 1.0.0
author: Marc
applyTo: "powerpages.config.json,**/powerpages.config.json"
tags:
  - power-pages
  - restart
  - admin-api
  - operations
---

# Restart a Power Pages Code Site

> **Trigger**: "Restart the site" or "Changes not reflected after deploy"

Restart a Power Pages site programmatically using the Power Platform Admin REST
API. There is **no PAC CLI command** to restart a site.

## When to Restart

| Scenario | Restart Needed? |
|---|---|
| Auth / security settings changed | **Yes** |
| Site settings (type 9) created or modified | **Yes** |
| Table permissions (type 18) created or modified | **Yes** |
| Web roles changed | **Yes** |
| UI / content-only changes (HTML, CSS, JS) | **No** — deploy is sufficient |
| Sample data inserted | **No** |

## Prerequisites

- Azure CLI installed (`az` available).
- Logged in to Azure (`az login` completed).
- Know your Power Platform **Environment ID** (from `pac env list`).
- Know your **Website ID** (from the Admin API — different from `powerpagesiteid` in Dataverse).

## Step-by-Step Procedure

### Phase 1: Authenticate

The Admin REST API uses `https://api.powerplatform.com` as the OAuth resource,
NOT the org URL.

```powershell
$token = az account get-access-token --resource "https://api.powerplatform.com" --query accessToken -o tsv
$headers = @{
  "Authorization" = "Bearer $token"
  "Content-Type"  = "application/json"
}
```

### Phase 2: Get Environment ID

```powershell
# From pac env list — use the GUID in the Environment ID column
pac env list
# Example: $envId = "08690526-047d-ed9d-ab35-4528a98c0f4f"
```

### Phase 3: Get Website ID

The Website ID for the Admin API is **different** from the `powerpagesiteid` in
Dataverse. Query the Admin API to find it:

```powershell
$envId = "<your-environment-id>"
$websites = Invoke-RestMethod `
  -Uri "https://api.powerplatform.com/powerpages/environments/$envId/websites?api-version=2022-03-01-preview" `
  -Headers $headers
$websites.value | Format-Table name, id
# Pick the website ID for your site
$siteId = "<website-id-from-output>"
```

### Phase 4: Restart

```powershell
Invoke-RestMethod `
  -Uri "https://api.powerplatform.com/powerpages/environments/$envId/websites/$siteId/restart?api-version=2022-03-01-preview" `
  -Headers $headers `
  -Method Post
```

The API returns immediately. The actual restart takes **1–3 minutes**.

### Phase 5: Verify

1. Wait ~2 minutes after the restart call.
2. Open the site URL in a browser.
3. **Clear browser cache and hard reload** (Ctrl+Shift+R).
4. Verify changes are reflected.
5. Check browser DevTools console for errors.

## Complete Script

```powershell
# --- Configuration ---
$envId  = "<your-environment-id>"      # From pac env list
$siteId = "<your-website-id>"          # From Phase 3 above

# --- Authenticate ---
$token = az account get-access-token --resource "https://api.powerplatform.com" --query accessToken -o tsv
$headers = @{
  "Authorization" = "Bearer $token"
  "Content-Type"  = "application/json"
}

# --- Restart ---
$baseUrl = "https://api.powerplatform.com/powerpages/environments/$envId/websites/$siteId"
Invoke-RestMethod -Uri "$baseUrl/restart?api-version=2022-03-01-preview" -Headers $headers -Method Post
Write-Host "Restart initiated. Site will be available in 1-3 minutes."
```

## Known Website IDs (Reference)

| Site | Environment ID | Website ID |
|---|---|---|
| ProjectC | `08690526-047d-ed9d-ab35-4528a98c0f4f` | `67685b8f-7b26-460a-a4bc-109911c133e3` |

> Update this table as you deploy new sites.

## Common Mistakes & Warnings

- **No `pac pages restart` exists** — The PAC CLI has no restart command. You
  must use the Admin REST API or the Power Pages admin centre UI.
- **OAuth resource is `https://api.powerplatform.com`** — NOT the org URL
  (`https://orgXXX.crmY.dynamics.com`). Using the wrong resource returns 401.
- **Website ID ≠ powerpagesiteid** — The Admin API uses its own website ID,
  which you get from the GET websites endpoint. The Dataverse `powerpagesiteid`
  is a different GUID.
- **Restart takes 1–3 minutes** — Don't panic if the site is briefly
  unavailable. Check again after 2 minutes.
- **Clear browser cache after restart** — Stale cached assets can make it look
  like the restart didn't work. Always Ctrl+Shift+R.
