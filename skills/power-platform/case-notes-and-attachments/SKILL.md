---
name: power-platform-case-notes-and-attachments
description: >
  Use when the user asks to "add notes to cases", "attach files to cases",
  "create annotations", "link notes to incidents", "set up case notes",
  "fix note creation errors", or "implement case attachments".
  Handles the full annotation (note) lifecycle on Power Pages Code Sites:
  Dataverse site settings, table permissions, anti-forgery tokens, the
  @odata.bind linking pattern, file attachment base64 encoding, and
  troubleshooting common 403/500 errors.
version: 1.0.0
author: Marc
applyTo: "powerpages.config.json,**/powerpages.config.json"
tags:
  - power-pages
  - annotations
  - notes
  - attachments
  - incident
  - case-management
  - dataverse
  - web-api
---

# Case Notes & Attachments on Power Pages Code Sites

> **Trigger**: "Add notes to cases", "attach files to incidents", or "fix
> annotation errors"

Create, link, and display Dataverse `annotation` records (notes with optional
file attachments) against `incident` (case) records, via the Power Pages
`/_api/` Web API. This skill covers the full stack: site settings, table
permissions, TypeScript services, React components, and troubleshooting.

## Prerequisites

- Power Pages Code Site deployed at least once.
- Azure CLI installed (`az account get-access-token` available).
- PAC CLI authenticated (`pac auth who` succeeds).
- **setup-permissions** skill completed for the `incident` table.
- **setup-webapi** skill completed (shared `powerPagesApi.ts` client exists).

## Before You Start

1. Use the **Dataverse MCP** to verify:
   - The `annotation` table exists (it's a system table, always present).
   - Existing `Webapi/annotation/*` and `Webapi/incident/*` site settings for your site.
2. Use the **Microsoft Learn MCP** to check current `/_api/` annotation syntax.

---

## Critical Lessons Learned

> **READ THIS FIRST** — These are hard-won lessons from production debugging.
> Skipping any of these WILL cause failures.

### 1. The `$ref` Association Pattern Does NOT Work on Code Sites

```
POST /_api/incidents({id})/Incident_Annotation/$ref
→ 500 Internal Server Error (always)
```

The OData `$ref` endpoint for associating annotations with incidents is
**broken on Power Pages Code Sites**. Do NOT use the two-step pattern
(create annotation → `$ref` associate). It will always return 500.

### 2. Use `@odata.bind` in the POST Body Instead

The correct pattern is to include `objectid_incident@odata.bind` directly
in the annotation POST body:

```typescript
POST /_api/annotations
{
  "subject": "Portal Note",
  "notetext": "User's note text",
  "objectid_incident@odata.bind": "/incidents({incidentId})"
}
```

The binding URI format is `/incidents({guid})` — **no** `/_api/` prefix.

### 3. Use Wildcard `*` for Field Settings

Both `Webapi/incident/fields` and `Webapi/annotation/fields` should be set
to `*` (wildcard). Explicit field lists cause 403 errors because:
- The `@odata.bind` pattern internally accesses attributes not in your list.
- The `$ref` endpoint (before we abandoned it) also accesses unknown fields.
- Wildcard is already the standard for `knowledgearticle` — use it everywhere.

### 4. Annotation Table Permission Needs `write=true`

The annotation table permission MUST include `write=true` in addition to
`create=true`. If you only enable create, the PATCH fallback (used to link
orphaned annotations) will fail with 403. Full permission set:
`read=true, create=true, write=true, append=true, appendto=true`.

### 5. Incident Table Permission Needs `appendto=true`

The incident table permission must have `appendto=true` to allow annotations
to be linked to it. Full recommended set:
`read=true, create=true, write=true, append=true, appendto=true`.

### 6. Site Settings Are Per-Site — Never Hardcode IDs

Always discover the site ID dynamically:
```powershell
$sites = Invoke-RestMethod -Uri "$baseUri/powerpagesites?`$select=powerpagesiteid,name"
$siteId = ($sites.value | Where-Object { $_.name -like "*YourSiteName*" }).powerpagesiteid
```
Different scripts previously used different site IDs (`e84ce96b-...` vs
`143708f4-...`), causing settings to bind to the wrong site.

### 7. Anti-Forgery Token: Use `/_layout/tokenhtml`

Code Sites do NOT inject a `<meta __RequestVerificationToken>` tag. Fetch from:
```
GET /_layout/tokenhtml
→ <input name="__RequestVerificationToken" type="hidden" value="TOKEN" />
```
Parse the `value="..."` from the HTML. Cache it — it's session-scoped.

---

## Step-by-Step Procedure

### Phase 1: Create Site Settings

Create a PowerShell script that dynamically finds the site and upserts settings.

```powershell
$envUrl = "https://<your-org>.crm.dynamics.com"
$token = az account get-access-token --resource $envUrl --query accessToken -o tsv
$headers = @{
  "Authorization"    = "Bearer $token"
  "Content-Type"     = "application/json"
  "OData-MaxVersion" = "4.0"
  "OData-Version"    = "4.0"
}
$baseUri = "$envUrl/api/data/v9.2"

# Discover site ID dynamically
$sites = (Invoke-RestMethod -Uri "$baseUri/powerpagesites?`$select=powerpagesiteid,name" -Headers $headers).value
$siteId = ($sites | Where-Object { $_.name -like "*YourSite*" }).powerpagesiteid

function Set-SiteSetting {
  param([string]$Name, [string]$Value)
  $filter = "powerpagecomponenttype eq 9 and name eq '$Name' and _powerpagesiteid_value eq $siteId"
  $existing = (Invoke-RestMethod -Uri "$baseUri/powerpagecomponents?`$filter=$filter&`$select=powerpagecomponentid,content" -Headers $headers).value
  $contentJson = @{ value = $Value; websiteid = $siteId } | ConvertTo-Json -Compress

  if ($existing.Count -gt 0) {
    $body = @{ content = $contentJson } | ConvertTo-Json
    Invoke-RestMethod -Uri "$baseUri/powerpagecomponents($($existing[0].powerpagecomponentid))" -Headers $headers -Method Patch -Body $body
  } else {
    $body = @{
      name = $Name; powerpagecomponenttype = 9; content = $contentJson
      "powerpagesiteid@odata.bind" = "/powerpagesites($siteId)"
    } | ConvertTo-Json
    Invoke-RestMethod -Uri "$baseUri/powerpagecomponents" -Headers $headers -Method Post -Body $body
  }
}

# Required settings — use wildcard for both
Set-SiteSetting "Webapi/annotation/enabled" "true"
Set-SiteSetting "Webapi/annotation/fields" "*"
Set-SiteSetting "Webapi/annotation/disableodatafilter" "false"

# Incident settings (if not already created by setup-permissions)
Set-SiteSetting "Webapi/incident/enabled" "true"
Set-SiteSetting "Webapi/incident/fields" "*"
Set-SiteSetting "Webapi/incident/disableodatafilter" "false"
```

### Phase 2: Create Table Permissions

```powershell
# Get web roles for the site
$roleFilter = "powerpagecomponenttype eq 11 and _powerpagesiteid_value eq $siteId"
$webRoles = (Invoke-RestMethod -Uri "$baseUri/powerpagecomponents?`$filter=$roleFilter&`$select=powerpagecomponentid,name" -Headers $headers).value
$roleIds = $webRoles | ForEach-Object { $_.powerpagecomponentid }

function Set-TablePermission {
  param([string]$DisplayName, [string]$EntityName, [hashtable]$Rights)
  $permFilter = "powerpagecomponenttype eq 18 and _powerpagesiteid_value eq $siteId"
  $allPerms = (Invoke-RestMethod -Uri "$baseUri/powerpagecomponents?`$filter=$permFilter&`$select=powerpagecomponentid,content" -Headers $headers).value
  $existing = $allPerms | Where-Object { ($_.content | ConvertFrom-Json).entitylogicalname -eq $EntityName }

  $contentObj = @{
    entityname = $DisplayName; entitylogicalname = $EntityName; scope = 756150000
    read = $Rights.read; create = $Rights.create; write = $Rights.write
    append = $Rights.append; appendto = $Rights.appendto; delete = $Rights.delete
    parentrelationship = $null; parententitypermission = $null
    contactrelationship = $null; accountrelationship = $null
    childTablePermissions = @(); adx_entitypermission_webrole = $roleIds
    permissionfetchxml = $null
  }
  $contentJson = $contentObj | ConvertTo-Json -Compress

  if ($existing.Count -gt 0) {
    $body = @{ content = $contentJson } | ConvertTo-Json
    Invoke-RestMethod -Uri "$baseUri/powerpagecomponents($($existing[0].powerpagecomponentid))" -Headers $headers -Method Patch -Body $body
  } else {
    $body = @{
      name = $DisplayName; powerpagecomponenttype = 18; content = $contentJson
      "powerpagesiteid@odata.bind" = "/powerpagesites($siteId)"
    } | ConvertTo-Json
    Invoke-RestMethod -Uri "$baseUri/powerpagecomponents" -Headers $headers -Method Post -Body $body
  }
}

# Annotation: read + create + write + append + appendto (write needed for PATCH fallback)
Set-TablePermission "Annotation - Global CRUD" "annotation" @{
  read=$true; create=$true; write=$true; append=$true; appendto=$true; delete=$false
}

# Incident: read + create + write + append + appendto
Set-TablePermission "Incident - Global CRUD" "incident" @{
  read=$true; create=$true; write=$true; append=$true; appendto=$true; delete=$false
}
```

### Phase 3: Restart the Site

Site settings and table permissions require a restart:

```powershell
$ppToken = az account get-access-token --resource "https://api.powerplatform.com" --query accessToken -o tsv
$ppHeaders = @{ "Authorization" = "Bearer $ppToken"; "Content-Type" = "application/json" }
$envId = "<environment-guid>"  # From pac env list
$websiteId = "<website-guid>"  # From GET /powerpages/environments/{envId}/websites
Invoke-RestMethod -Uri "https://api.powerplatform.com/powerpages/environments/$envId/websites/$websiteId/restart?api-version=2022-03-01-preview" -Headers $ppHeaders -Method Post
```

### Phase 4: TypeScript Types

Add to `src/types/dataverse.ts`:

```typescript
export interface Annotation {
  annotationid: string;
  subject?: string;
  notetext?: string;
  filename?: string;
  filesize?: number;
  mimetype?: string;
  isdocument?: boolean;
  createdon: string;
  _objectid_value?: string;
}
```

### Phase 5: Implement the Add Note Function

This is the **proven working pattern** with fallback chain:

```typescript
import { apiRequest, apiRequestRaw, type ODataResponse } from '../services/powerPagesApi';
import type { Annotation } from '../types/dataverse';

async function addNoteToIncident(
  incidentId: string,
  subject: string,
  noteText: string,
  file?: File
): Promise<void> {
  const body: Record<string, unknown> = { subject, notetext: noteText };

  if (file) {
    body.isdocument = true;
    body.documentbody = await fileToBase64(file);
    body.filename = file.name;
    body.mimetype = file.type || 'application/octet-stream';
  }

  // Strategy 1: POST with @odata.bind in body (preferred, single request)
  const bindingFormats = [
    `/incidents(${incidentId})`,        // Most common working format
    `incidents(${incidentId})`,          // No leading slash variant
    `/_api/incidents(${incidentId})`,    // Full path variant
  ];

  let annotationId: string | null = null;

  for (const bindingUri of bindingFormats) {
    try {
      const postBody = { ...body, 'objectid_incident@odata.bind': bindingUri };
      const res = await apiRequestRaw('/annotations', { method: 'POST', body: postBody });
      annotationId = res.headers.get('entityid');
      console.debug(`[Notes] POST+bind succeeded: "${bindingUri}" → ${annotationId}`);
      break;
    } catch {
      console.warn(`[Notes] POST+bind failed: "${bindingUri}"`);
    }
  }

  // Strategy 2: Bare POST + PATCH to link (fallback)
  if (!annotationId) {
    const bareRes = await apiRequestRaw('/annotations', { method: 'POST', body });
    annotationId = bareRes.headers.get('entityid');
    if (!annotationId) throw new Error('Failed to create annotation');

    let linked = false;
    for (const uri of [`/incidents(${incidentId})`, `/_api/incidents(${incidentId})`]) {
      try {
        await apiRequest(`/annotations(${annotationId})`, {
          method: 'PATCH',
          body: { 'objectid_incident@odata.bind': uri },
        });
        linked = true;
        break;
      } catch { /* try next */ }
    }
    if (!linked) throw new Error('Note created but could not be linked to case.');
  }
}

function fileToBase64(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve((reader.result as string).split(',')[1]);
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
}
```

### Phase 6: Fetch Notes for a Case

```typescript
async function fetchNotesForIncident(incidentId: string): Promise<Annotation[]> {
  const result = await apiRequest<ODataResponse<Annotation>>(
    `/annotations?$select=annotationid,subject,notetext,filename,filesize,mimetype,isdocument,createdon` +
    `&$filter=_objectid_value eq ${incidentId}&$orderby=createdon desc`
  );
  return result.value;
}
```

### Phase 7: Render Notes UI (React)

```tsx
{notes.map((n) => (
  <div key={n.annotationid} className="note-card">
    <div className="note-header">
      <strong>{n.subject || 'Note'}</strong>
      <span className="note-date">{n.createdon?.slice(0, 10)}</span>
    </div>
    {n.notetext && <p className="note-body">{n.notetext}</p>}
    {n.isdocument && n.filename && (
      <div className="note-attachment">
        📎 {n.filename} {n.filesize ? `(${(n.filesize / 1024).toFixed(1)} KB)` : ''}
      </div>
    )}
  </div>
))}
```

---

## Troubleshooting Guide

| Error | Code | Cause | Fix |
|---|---|---|---|
| "Attribute * in table incident is not enabled for Web Api" | 90040101 | `Webapi/incident/fields` is too restrictive or missing | Set to `*` (wildcard) |
| "Resource not found for segment annotation" | 9004010C | `Webapi/annotation/enabled` missing for this site | Create setting bound to correct site |
| "You don't have permission to update annotation table" | 403 | Annotation table permission `write=false` | Set `write=true` on annotation permission |
| "An unexpected error occurred" on `$ref` | 500 | `Incident_Annotation/$ref` not supported on Code Sites | Use `@odata.bind` in POST body instead |
| "An unexpected error occurred" on POST with bind | 500 | Wrong `@odata.bind` URI format | Try `/incidents(id)` (no `/_api/` prefix) |
| "Request validation failed" | 403 | Empty anti-forgery token | Use `/_layout/tokenhtml` (not meta tag) |
| "AttributePermissionIsMissing" on annotation POST | 90040101 | Field in body not in `Webapi/annotation/fields` | Set to `*` (wildcard) |
| Notes don't appear after creation | — | `_objectid_value` filter returns empty | Annotation not linked — check binding step logs |

## Diagnostic Script

When notes aren't working, run this diagnostic to check all settings:

```powershell
# 1. Find site ID
$sites = (Invoke-RestMethod -Uri "$baseUri/powerpagesites?`$select=powerpagesiteid,name" -Headers $headers).value
$siteId = ($sites | Where-Object { $_.name -like "*YourSite*" }).powerpagesiteid

# 2. Check site settings
$filter = "powerpagecomponenttype eq 9 and (startswith(name,'Webapi/incident/') or startswith(name,'Webapi/annotation/')) and _powerpagesiteid_value eq $siteId"
$settings = (Invoke-RestMethod -Uri "$baseUri/powerpagecomponents?`$filter=$filter&`$select=name,content" -Headers $headers).value
$settings | ForEach-Object { $c = $_.content | ConvertFrom-Json; Write-Host "$($_.name) = $($c.value) [websiteid=$($c.websiteid)]" }

# 3. Check table permissions
$permFilter = "powerpagecomponenttype eq 18 and _powerpagesiteid_value eq $siteId"
$perms = (Invoke-RestMethod -Uri "$baseUri/powerpagecomponents?`$filter=$permFilter&`$select=content" -Headers $headers).value
$perms | ForEach-Object {
  $c = $_.content | ConvertFrom-Json
  if ($c.entitylogicalname -in @('incident','annotation')) {
    Write-Host "$($c.entitylogicalname): read=$($c.read) create=$($c.create) write=$($c.write) append=$($c.append) appendto=$($c.appendto) roles=$($c.adx_entitypermission_webrole.Count)"
  }
}

# 4. Check for orphaned annotations
$orphans = (Invoke-RestMethod -Uri "$baseUri/annotations?`$filter=_objectid_value eq null and subject eq 'Portal Note'&`$select=annotationid,createdon&`$top=5" -Headers $headers).value
Write-Host "Orphaned 'Portal Note' annotations: $($orphans.Count)"
```

## Reference: Working ProjectC Implementation

See `ProjectC/src/pages/CaseDetail.tsx` for the production implementation:
- `handleAddNote()` — full add-note flow with POST+bind → PATCH fallback
- `useEffect` — fetches incident + annotations on load
- `fileToBase64()` — converts file to base64 for `documentbody`

See `ProjectC/scripts/fix-notes-final.ps1` for the production setup script.
See `ProjectC/scripts/diagnose-settings.ps1` for the diagnostic script.
