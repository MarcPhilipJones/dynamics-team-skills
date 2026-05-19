---
name: web-api-odata-bind-security
description: >
  Complete guide to configuring Power Pages security for @odata.bind lookup
  references in Web API create/update operations. Covers the TWO requirements
  (Web API site settings + table permissions with AppendTo) that BOTH must be
  present for every table referenced via @odata.bind.
version: 1.0.0
author: Marc
applyTo: "**/*.ts,**/*.tsx,**/scripts/*.ps1"
tags:
  - power-pages
  - security
  - web-api
  - odata-bind
  - table-permissions
  - troubleshooting
---

# Power Pages Web API — @odata.bind Security Requirements

## When to Use This Skill

- You see `"You don't have permission to associate or disassociate table X to Y"`
- You're creating a record with `@odata.bind` lookup references via the Power Pages `/_api/` Web API
- You've set up table permissions but lookups still fail with 403/permission errors

## The Two-Part Rule

When a Power Pages Web API `POST` or `PATCH` includes an `@odata.bind` reference
(e.g. `"pricelevelid@odata.bind": "/pricelevels(guid)"`), Power Pages enforces
**TWO independent security checks** on the **referenced (target) table**:

### 1. Web API Site Settings (powerpagecomponenttype = 9)

The target table MUST have these three site settings:

```
Webapi/<tablename>/enabled = true
Webapi/<tablename>/fields = *
Webapi/<tablename>/disableodatafilter = false
```

Without these, the portal runtime doesn't recognise the table at all — even if
you only reference it via `@odata.bind` and never query it directly.

### 2. Table Permission (powerpagecomponenttype = 18)

The target table MUST have a table permission with:

- `read: true` — required for the runtime to resolve the GUID
- `appendto: true` — required for the association to be authorised
- Assigned to the user's **web role** via `adx_entitypermission_webrole`
- `scope: 756150000` (Global) is simplest for lookup/reference tables

### If Either is Missing

| Missing | Error Message |
|---|---|
| Web API settings only | `"Resource not found for the segment <table>"` (404) |
| Table permission only | `"You don't have permission to read the <table> table"` |
| AppendTo on TP | `"You don't have permission to associate or disassociate table <target> to <source>"` |
| Both | `"Resource not found"` or `"You don't have permission to read"` |

## Common Lookup Tables That Need This

When creating **Opportunities** or **Opportunity Products**, these tables are
commonly referenced via `@odata.bind` and ALL need both settings + permissions:

| Table | Logical Name | Why Referenced |
|---|---|---|
| Price List | `pricelevel` | `pricelevelid@odata.bind` on opportunity |
| Product | `product` | `productid@odata.bind` on opportunity product |
| Unit | `uom` | `uomid@odata.bind` on opportunity product |
| Currency | `transactioncurrency` | Implicit on opportunity (auto-set from price list) |
| Contact | `contact` | `customerid_contact@odata.bind` on opportunity |
| Lead | `lead` | `originatingleadid@odata.bind` on opportunity |
| Account | `account` | `<prefix>_dealerid@odata.bind` on custom tables |

## How to Create Both via PowerShell

### Web API Site Settings

```powershell
$envUrl  = "https://<org>.crm.dynamics.com"
$siteId  = "<powerpagesiteid>"  # From website.yml
$token   = az account get-access-token --resource $envUrl --query accessToken -o tsv
$h = @{
  Authorization = "Bearer $token"; "Content-Type" = "application/json"
  "OData-MaxVersion" = "4.0"; "OData-Version" = "4.0"; Accept = "application/json"
}
Add-Type -AssemblyName System.Web

function Set-WebApiSetting {
  param([string]$Name, [string]$Value)
  $content = @{ value = $Value; websiteid = $siteId } | ConvertTo-Json -Compress
  $body = @{
    name = $Name; powerpagecomponenttype = 9; content = $content
    "powerpagesiteid@odata.bind" = "/powerpagesites($siteId)"
  } | ConvertTo-Json
  Invoke-RestMethod -Uri "$envUrl/api/data/v9.2/powerpagecomponents" `
    -Method Post -Headers $h -Body ([System.Text.Encoding]::UTF8.GetBytes($body))
}

# Example: enable pricelevel
Set-WebApiSetting -Name "Webapi/pricelevel/enabled"            -Value "true"
Set-WebApiSetting -Name "Webapi/pricelevel/fields"             -Value "*"
Set-WebApiSetting -Name "Webapi/pricelevel/disableodatafilter" -Value "false"
```

### Table Permission

```powershell
$webRole = "<authenticated-users-webrole-id>"

function New-TablePermission {
  param([string]$Id, [string]$Name, [string]$LogicalName,
        [bool]$Read, [bool]$AppendTo)
  $contentObj = @{
    contactrelationship = $null; entityname = $Name; delete = $false
    parentrelationship = $null; appendto = $AppendTo; scope = 756150000
    create = $false; accountrelationship = $null; childTablePermissions = @()
    write = $false; append = $false; entitylogicalname = $LogicalName
    parententitypermission = $null; read = $Read; permissionfetchxml = $null
    adx_entitypermission_webrole = @($webRole)
  }
  $body = @{
    powerpagecomponentid = $Id; name = $Name; powerpagecomponenttype = 18
    content = ($contentObj | ConvertTo-Json -Compress -Depth 5)
    "powerpagesiteid@odata.bind" = "/powerpagesites($siteId)"
  } | ConvertTo-Json
  Invoke-RestMethod -Uri "$envUrl/api/data/v9.2/powerpagecomponents" `
    -Method Post -Headers $h -Body ([System.Text.Encoding]::UTF8.GetBytes($body))
}

# Example: pricelevel — read + appendto only
New-TablePermission -Id (New-Guid) -Name "Price Level - Global Read" `
  -LogicalName "pricelevel" -Read $true -AppendTo $true
```

## Critical Gotchas

### 1. powerpagecomponenttype MUST be 18 for Table Permissions
Type `10` is a generic component — the permission engine silently ignores it.
Type `9` = site setting, `11` = web role, `18` = table permission.

### 2. Content JSON must use flat fields, NOT nested
**WRONG:** `{ "right": { "read": true, "write": true } }`
**RIGHT:** `{ "read": true, "write": true, "adx_entitypermission_webrole": [...] }`

### 3. Web role key must be `adx_entitypermission_webrole`, not `webRoles`
The runtime only reads the `adx_entitypermission_webrole` array.

### 4. Site restart required
Table permission and site setting changes are cached server-side.
After creating/updating, restart via the Admin API:
```
POST https://api.powerplatform.com/powerpages/environments/{envId}/websites/{siteId}/restart?api-version=2022-03-01-preview
```

### 5. The "source" table also needs Append
For `@odata.bind` on create, the table being **created** (e.g. opportunity)
needs `append: true`. The table being **referenced** (e.g. pricelevel) needs
`appendto: true`. Both are required.

### 6. YAML files get overwritten on deploy
`pac pages upload-code-site` deploys `.powerpages-site/table-permissions/*.yml`
and `.powerpages-site/site-settings/*.yml`. Always keep YAML in sync with
Dataverse, or the next deploy will revert your changes.

## Checklist for New @odata.bind References

For every `@odata.bind` in your code:

- [ ] Target table has `Webapi/<table>/enabled = true` site setting
- [ ] Target table has `Webapi/<table>/fields = *` site setting
- [ ] Target table has table permission with `read: true, appendto: true`
- [ ] Table permission is `powerpagecomponenttype = 18`
- [ ] Table permission content uses `adx_entitypermission_webrole` (flat format)
- [ ] Source table has table permission with `append: true`
- [ ] YAML files exist in `.powerpages-site/` for both settings and permissions
- [ ] Site restarted after changes

## Key Takeaway

> **Every table referenced via `@odata.bind` needs BOTH Web API site settings
> AND a table permission with `appendto: true` — even if you never query that
> table directly. Missing either one causes a different error message, making
> diagnosis confusing.**

## HARD LIMITATION: System Lookup Tables (Currency, Price List, Product, UOM)

**Power Pages `/_api/` CANNOT set these lookups via `@odata.bind` — not on POST, not on PATCH.**

All of these approaches were tested and FAILED:

| Approach | Result |
|---|---|
| `@odata.bind` on POST | 403 "permission to associate" |
| `@odata.bind` on PATCH | 403 "permission to associate" |
| `_transactioncurrencyid_value` (direct GUID) | 400 "Common Data Service error" |
| Currency inheritance from contact | Ignored — always uses org base currency |
| Changing org base currency via API | Appears to succeed but doesn't persist |
| Web API settings + table permissions + AppendTo | Still 403 — even after site restart |

### The ONLY Working Solution: Logic App HTTP Trigger

1. Portal creates the opportunity with `customerid_contact@odata.bind` + `originatingleadid@odata.bind` only (these work)
2. Portal calls a **Logic App HTTP endpoint** passing `{ opportunityId: "guid" }`
3. Logic App uses the **Dataverse connector** (full server-side permissions) to:
   - Set `_transactioncurrencyid_value` = currency GUID
   - Set `_pricelevelid_value` = Price List GUID
4. Portal then creates write-in products (`isproductoverridden=true`)

### Logic App Setup Pattern

- **Type**: Consumption, HTTP trigger
- **Connection**: Reuse existing Dataverse connector (`commondataservice`)
- **Actions**: Two "Update a row" steps using `_value` field format (NOT `@odata.bind`)
- **Response**: Return `{ status: "ok", opportunityId }` so portal knows it succeeded
- **Important**: After ARM deployment, must open + save in Azure Portal to activate trigger
- **SAS URL**: Store in code (presales/demo) or GitHub Secrets / Key Vault (production)

### Reference Implementation Pattern

- Logic App: `la-<project>-opp-currency-pricelevel` in `rg-<project>` (your chosen region)
- Definition: stored as a JSON file alongside the deploy script
- Deploy script: parameterised PowerShell that takes resource group, region, and Dataverse env URL
