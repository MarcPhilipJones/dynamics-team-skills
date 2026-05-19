---
name: power-pages-add-sample-data
description: >
  Use when the user asks to "add sample data", "seed the database", "populate tables",
  "create test data", or "add demo records". Inserts sample records into Dataverse
  tables via the OData API.
version: 1.0.0
author: Marc
applyTo: "powerpages.config.json,**/powerpages.config.json"
tags:
  - power-pages
  - sample-data
  - dataverse
  - odata
  - seeding
---

# Add Sample Data to Dataverse

> **Trigger**: "Add sample data for [table name]"

Populate Dataverse tables with realistic sample records via the OData Web API.
Handles parent-child relationships, lookups, and token refresh for bulk inserts.

## Prerequisites

- Tables already created (see setup-datamodel skill).
- Azure CLI installed for token acquisition.
- Know the table logical names and column definitions.

## Before You Start

1. Use the **Dataverse MCP** to verify table schemas and confirm column names.
2. Check if any records already exist to avoid duplicates.

## Step-by-Step Procedure

### Phase 1: Discovery

1. Ask the user which tables need sample data.
2. Determine the number of records per table (default: 10-20).
3. Identify insertion order based on relationships (parents first).
4. Confirm the plan with the user.

### Phase 2: Authenticate

```powershell
$envUrl = "https://<your-org>.crm.dynamics.com"
$token = az account get-access-token --resource $envUrl --query accessToken -o tsv
$headers = @{
  "Authorization" = "Bearer $token"
  "Content-Type"  = "application/json"
  "OData-MaxVersion" = "4.0"
  "OData-Version" = "4.0"
  "Prefer" = "return=representation"
}
```

### Phase 3: Prepare Sample Data

Generate realistic sample data (not lorem ipsum). Use:
- Real-sounding names, titles, descriptions
- Realistic dates (within the last 1-2 years)
- Appropriate status codes and option set values
- Varied data (not all the same values)

### Phase 4: Insert Parent Records First

```powershell
# Insert parent/independent tables first
$accounts = @(
  @{ name = "Contoso Ltd"; address1_city = "Seattle" },
  @{ name = "Fabrikam Inc"; address1_city = "Portland" },
  @{ name = "Adventure Works"; address1_city = "Redmond" }
)

$createdAccounts = @()
foreach ($acc in $accounts) {
  $body = $acc | ConvertTo-Json
  $result = Invoke-RestMethod -Uri "$envUrl/api/data/v9.2/accounts" `
    -Headers $headers -Method Post -Body $body
  $createdAccounts += $result
  Write-Host "Created account: $($result.name)"
}
```

### Phase 5: Insert Child Records with Lookups

```powershell
# Use @odata.bind for lookup fields
$incidents = @(
  @{
    title = "Website login issue"
    description = "Users unable to login via SSO"
    "customerid_account@odata.bind" = "/accounts($($createdAccounts[0].accountid))"
    prioritycode = 1
  },
  @{
    title = "Data export not working"
    description = "CSV export returns empty file"
    "customerid_account@odata.bind" = "/accounts($($createdAccounts[1].accountid))"
    prioritycode = 2
  }
)

$recordCount = 0
foreach ($inc in $incidents) {
  # Refresh token every 20 records
  $recordCount++
  if ($recordCount % 20 -eq 0) {
    $token = az account get-access-token --resource $envUrl --query accessToken -o tsv
    $headers["Authorization"] = "Bearer $token"
    Write-Host "Token refreshed at record $recordCount"
  }

  $body = $inc | ConvertTo-Json
  Invoke-RestMethod -Uri "$envUrl/api/data/v9.2/incidents" `
    -Headers $headers -Method Post -Body $body
}
```

### Phase 6: Verify

```powershell
# Count records in each table
$tables = @("accounts", "incidents")
foreach ($t in $tables) {
  $count = (Invoke-RestMethod -Uri "$envUrl/api/data/v9.2/${t}?`$count=true&`$top=0" `
    -Headers $headers)."@odata.count"
  Write-Host "${t}: $count records"
}
```

## Common Mistakes & Warnings

- **Insert order matters** -- Always create parent records before children.
  Lookup fields reference parent record IDs.
- **Use `@odata.bind` for lookups** -- NOT the raw GUID in the lookup field.
  Format: `"fieldname@odata.bind": "/entities(guid)"`.
- **Token expires** -- Refresh the token every ~20 records for bulk inserts.
  `az account get-access-token` returns a fresh token each call.
- **Prefer return=representation** -- Include this header to get the created
  record back (with the generated ID) in the response.
- **Avoid duplicate data** -- Check existing record counts before inserting.
- **Use realistic data** -- Not "Test 1", "Test 2". Use real-sounding names,
  addresses, descriptions.
- **Option set values are integers** -- Status, priority, category fields use
  integer codes, not labels. Check metadata for valid values.
