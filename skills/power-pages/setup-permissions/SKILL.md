---
name: power-pages-setup-permissions
description: >
  Use when the user asks to "set up permissions", "configure table permissions",
  "enable Web API", "fix 403 error", "fix 404 API error", or "create site settings".
  Creates Dataverse Web API site settings and table permissions via the
  Dataverse OData API.
version: 1.0.0
author: Marc
applyTo: "powerpages.config.json,**/powerpages.config.json"
tags:
  - power-pages
  - permissions
  - site-settings
  - web-api
  - security
---

# Set Up Table Permissions & Web API Site Settings

> **Trigger**: "Enable Web API access for [table]" or "Fix 403/404 API errors"

Configure the two sides of Power Pages data access:
1. **Site settings** (Webapi/* entries) -- created via Dataverse OData API.
2. **Table permissions** -- created via Dataverse OData API (same method).

## Prerequisites

- Authenticated PAC CLI session (`pac auth who` succeeds).
- Azure CLI installed.
- Site deployed at least once.
- Know your site ID (`pac paportal list` to find it).

## Code Sites v2 Notes

> Both **site settings** (`powerpagecomponent` type 9) and **table permissions**
> (`powerpagecomponent` type 18) are created via the Dataverse OData API.
> A site restart is **required** after creating table permissions before the
> runtime picks them up. Use the **restart-site** skill to restart programmatically.
>
> See the **code-sites-v2-reference** skill for the full `powerpagecomponent`
> type reference table and YAML overwrite behaviour.

## Step-by-Step Procedure

### Phase 1: Authenticate

```powershell
$envUrl = "https://<your-org>.crm.dynamics.com"
$token = az account get-access-token --resource $envUrl --query accessToken -o tsv
$headers = @{
  "Authorization" = "Bearer $token"
  "Content-Type"  = "application/json"
  "OData-MaxVersion" = "4.0"
  "OData-Version" = "4.0"
}
```

### Phase 2: Get the Correct Runtime Site ID

> **CRITICAL — Dual Site ID Trap**: Code Sites can have **TWO+** `powerpagesites`
> records with the same name — one created by `pac pages upload-code-site` and
> one created when the site is activated/converted in Design Studio. The runtime
> uses the **Design Studio record**, not the PAC CLI one.
>
> **Impact**: PAC CLI uploads JS/CSS to ITS site record, but the browser serves
> from the Design Studio site → **code changes never appear**, and settings bound
> to the wrong ID cause 404 errors (`9004010C`).
>
> **Best fix**: Delete the extra site records and set `.powerpages-site/website.yml`
> to the runtime site ID. Then `pac pages upload-code-site` deploys directly
> to the live site (like ProjectB, which has ONE site record and works perfectly).
>
> **NEVER delete `.powerpages-site/`** — `pac pages upload-code-site` will create
> a NEW powerpagesites record, making the problem worse.

To find the correct runtime site ID, check which `powerpagesiteid` the
**Design Studio-created settings** (e.g. authentication settings) are bound to:

```powershell
# Step 1: Find all powerpagesites records with the site name
$sites = (Invoke-RestMethod -Uri "$envUrl/api/data/v9.2/powerpagesites?`$filter=contains(name,'YOUR_SITE_NAME')&`$select=powerpagesiteid,name" -Headers $headers).value
$sites | ForEach-Object { Write-Host "  $($_.name) => $($_.powerpagesiteid)" }
# If only ONE record appears, use that ID. If TWO appear, continue to step 2.

# Step 2: Check which ID has the auth settings (created by Design Studio)
foreach ($s in $sites) {
  $id = $s.powerpagesiteid
  $count = (Invoke-RestMethod -Uri "$envUrl/api/data/v9.2/powerpagecomponents?`$filter=powerpagecomponenttype eq 9 and _powerpagesiteid_value eq $id and startswith(name,'Authentication/')&`$select=powerpagecomponentid" -Headers $headers).value.Count
  Write-Host "  $id => $count auth settings"
}
# The ID with authentication settings is the RUNTIME site ID. Use that one.

# Step 3 (recommended): Delete extra powerpagesites records
# Delete the NON-runtime IDs so PAC CLI has no choice but to use the runtime site
Invoke-RestMethod -Uri "$envUrl/api/data/v9.2/powerpagesites($extraSiteId)" -Headers $headers -Method Delete

# Step 4: Update website.yml to point to the runtime site
# Get header/footer/language template IDs for the runtime site:
$templates = (Invoke-RestMethod -Uri "$envUrl/api/data/v9.2/powerpagecomponents?`$filter=powerpagecomponenttype eq 8 and _powerpagesiteid_value eq $runtimeSiteId and (name eq 'Header' or name eq 'Footer')&`$select=powerpagecomponentid,name" -Headers $headers).value
$lang = (Invoke-RestMethod -Uri "$envUrl/api/data/v9.2/powerpagesitelanguages?`$filter=_powerpagesiteid_value eq $runtimeSiteId&`$select=powerpagesitelanguageid" -Headers $headers).value[0]
# Then write website.yml with id, headerwebtemplateid, footerwebtemplateid, defaultlanguage
```

> **Rule of thumb**: The site ID in `.powerpages-site/website.yml` (from PAC CLI)
> may NOT be the runtime ID. Always verify by checking which ID has auth settings.

### Phase 3: Create Web API Site Settings

For each table that needs API access, create THREE site settings:

```powershell
function New-SiteSetting {
  param([string]$Name, [string]$Value, [string]$SiteId)

  $body = @{
    name = $Name
    powerpagecomponenttype = 9
    content = (@{ value = $Value; websiteid = $SiteId } | ConvertTo-Json -Compress)
    "powerpagesiteid@odata.bind" = "/powerpagesites($SiteId)"
  } | ConvertTo-Json

  Invoke-RestMethod -Uri "$envUrl/api/data/v9.2/powerpagecomponents" `
    -Headers $headers -Method Post -Body $body
}

# Example: Enable Web API for 'incident' table
New-SiteSetting -Name "Webapi/incident/enabled" -Value "true" -SiteId $siteId
New-SiteSetting -Name "Webapi/incident/fields" -Value "incidentid,title,description,statuscode,createdon" -SiteId $siteId
New-SiteSetting -Name "Webapi/incident/disableodatafilter" -Value "false" -SiteId $siteId
```

**IMPORTANT**: The `fields` value MUST include the **primary key field** (e.g.,
`incidentid`) as the first item. Omitting it causes 403 errors (code `90040101`).

> **Tip**: Use `*` (wildcard) for the fields value when the entity is involved
> in `$ref` associations, `@odata.bind` operations, or complex queries.
> Restrictive field lists cause hard-to-debug failures with those patterns.

### Phase 4: Create Table Permissions (OData API)

First, get the web role component IDs for your site:

```powershell
$roles = Invoke-RestMethod -Uri "$envUrl/api/data/v9.2/powerpagecomponents?`$filter=powerpagecomponenttype eq 11 and _powerpagesiteid_value eq '$siteId'&`$select=powerpagecomponentid,name" -Headers $headers
$roles.value | Format-Table name, powerpagecomponentid
```

Then create table permissions using the `New-TablePermission` function:

```powershell
function New-TablePermission {
  param(
    [string]$Name,
    [string]$EntityLogicalName,
    [string]$SiteId,
    [string[]]$WebRoleIds,
    [bool]$Read     = $true,
    [bool]$Create   = $false,
    [bool]$Write    = $false,
    [bool]$Delete   = $false,
    [bool]$Append   = $false,
    [bool]$AppendTo = $false
  )

  $contentObj = @{
    entityname                   = $Name
    entitylogicalname            = $EntityLogicalName
    scope                        = 756150000  # Global
    read                         = $Read
    create                       = $Create
    write                        = $Write
    delete                       = $Delete
    append                       = $Append
    appendto                     = $AppendTo
    parentrelationship           = $null
    parententitypermission       = $null
    contactrelationship          = $null
    accountrelationship          = $null
    childTablePermissions        = @()
    adx_entitypermission_webrole = $WebRoleIds
    permissionfetchxml           = $null
  }

  $body = @{
    name                         = $Name
    powerpagecomponenttype       = 18
    content                      = ($contentObj | ConvertTo-Json -Compress -Depth 5)
    "powerpagesiteid@odata.bind" = "/powerpagesites($SiteId)"
  } | ConvertTo-Json -Depth 5

  Invoke-RestMethod -Uri "$envUrl/api/data/v9.2/powerpagecomponents" `
    -Headers $headers -Method Post -Body $body
}

# Example: Create read permission for 'incident' assigned to Anonymous + Authenticated
$anonRoleId = "<anonymous-role-component-id>"
$authRoleId = "<authenticated-role-component-id>"

New-TablePermission -Name "Incident - Global Read" `
  -EntityLogicalName "incident" `
  -SiteId $siteId `
  -WebRoleIds @($anonRoleId, $authRoleId)
```

**Scope values:**
- `756150000` = Global (all records)
- `756150001` = Contact (owner's records)
- `756150002` = Account (account's records)
- `756150003` = Parent table (related records via lookup)

After creating all permissions, **restart the site** using the **restart-site**
skill (Power Platform Admin REST API). There is no PAC CLI restart command.

> **Note**: API-created table permissions have been confirmed working for
> ProjectC and SSENTPortal. If they are not picked up after restart, verify
> the `_powerpagesiteid_value` matches your site and that web role IDs are
> correct. As a last resort, recreate in Design Studio UI.

### Phase 5: Verify

Test the API endpoint after settings are applied:

```powershell
# From the portal (authenticated browser session):
# GET https://yoursite.powerappsportals.com/_api/incidents?$select=incidentid,title&$top=5
```

## Table Permission Access Scope Reference

| Scope | Value | Use When |
|---|---|---|
| Global | All records | Public data, reference tables |
| Contact | Owner's records | User-owned data |
| Account | Account's records | Organization-scoped data |
| Parent table | Related records | Child records via lookup |

## Common Mistakes & Warnings

- **403 "AttributePermissionIsMissing"** (90040101) -- A field in `$select` is
  not in `Webapi/<entity>/fields`. Always include the primary key field.
- **404 "Resource not found for segment"** (9004010C) -- Missing
  `Webapi/<entity>/enabled` or `Webapi/<entity>/fields` site settings. Settings
  are per-website -- verify `_powerpagesiteid_value` matches your site ID.
  **Most common cause**: settings are bound to the wrong `powerpagesiteid` when
  two records exist (see Phase 2 "Dual Site ID Trap"). The PAC CLI site ID
  (from `website.yml`) and the runtime site ID (from Design Studio) can differ.
- **Site restart required after creating permissions** -- API-created table
  permissions require a site restart from the maker portal before the runtime
  picks them up.
- **Fallback to Design Studio** -- If API-created permissions still don't work
  after restart, recreate them in Design Studio UI as a fallback.
- **Settings from other sites don't apply** -- Each site has its own set of
  `powerpagecomponent` records scoped by `_powerpagesiteid_value`.
- **YAML overwrite trap** -- Site settings created via API will be **overwritten**
  on the next `pac pages upload-code-site` if a YAML file in
  `.powerpages-site/site-settings/` has a different value for the same setting.
  Always fix YAML source files too, or download the site after API changes:
  `pac pages download-code-site --rootPath "."`
  See the **code-sites-v2-reference** skill for details.
- **Use wildcard `*` for complex entities** -- Entities involved in `$ref`
  associations or `@odata.bind` operations should use `Webapi/<entity>/fields = *`
  to avoid unpredictable 403 errors from internal attribute access.
- **403 "No permission to associate contact to incident"** (90040106) -- When
  creating incidents with `customerid_contact@odata.bind`, the **Contact** table
  permission MUST have `Append = true` AND `AppendTo = true`. The **Incident**
  table permission also needs `Append = true`. Without both sides, the cross-table
  association fails. Standard permission set for this pattern:
  - Incident: Read + Create + Write + Append + AppendTo
  - Contact: Read + Append + AppendTo

## Related Skills

| Skill | When to Use |
|---|---|
| [restart-site](../restart-site/SKILL.md) | Restart site after creating permissions |
| [code-sites-v2-reference](../code-sites-v2-reference/SKILL.md) | Component type codes, YAML behaviour, v2 data model |
| [setup-webapi](../setup-webapi/SKILL.md) | TypeScript API client for the permissions you just created |
