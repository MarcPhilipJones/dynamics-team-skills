---
name: power-pages-setup-datamodel
description: >
  Use when the user asks to "create tables", "set up the data model",
  "design the database", "add columns", or "create relationships". Creates
  Dataverse tables, columns, and relationships for Power Pages via the OData API.
version: 1.0.0
author: Marc
applyTo: "powerpages.config.json,**/powerpages.config.json"
tags:
  - power-pages
  - dataverse
  - data-model
  - odata
---

# Set Up the Dataverse Data Model

> **Trigger**: "Create a data model for [entity description]"

Design and create Dataverse tables, columns, and relationships using the OData
EntityDefinitions API so that the site has structured data to surface.

## Prerequisites

- Authenticated PAC CLI session (`pac auth who` succeeds).
- Azure CLI installed (`az account get-access-token` works).
- Environment URL known (e.g., `https://<your-org>.crm.dynamics.com`).

## Before You Start

1. Use the **Dataverse MCP** to query existing tables and avoid name collisions:
   ```
   GET /api/data/v9.2/EntityDefinitions?$select=LogicalName,DisplayName
   ```
2. Use the **Microsoft Learn MCP** to verify current column type options
   and relationship syntax for any types you're unsure about.

## Step-by-Step Procedure

### Phase 1: Discovery

1. Ask the user what data their site needs to manage.
2. Map requirements to Dataverse tables and columns.
3. Identify relationships (1:N, N:1, N:N) between tables.
4. Present the proposed schema as a markdown table for review.
5. Get explicit approval before creating anything.

### Phase 2: Authenticate

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

### Phase 3: Create Tables

For each table, use the EntityDefinitions endpoint with deep-insert to create
the table and its columns in a single request:

```powershell
$body = @{
  "@odata.type" = "Microsoft.Dynamics.CRM.EntityMetadata"
  SchemaName = "cr8b0_mytable"
  DisplayName = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.Label"
    LocalizedLabels = @(@{
      "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
      Label = "My Table"
      LanguageCode = 1033
    })
  }
  DisplayCollectionName = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.Label"
    LocalizedLabels = @(@{
      "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
      Label = "My Tables"
      LanguageCode = 1033
    })
  }
  HasActivities = $false
  Attributes = @(
    @{
      "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
      SchemaName = "cr8b0_name"
      AttributeType = "String"
      MaxLength = 200
      DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
          "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
          Label = "Name"
          LanguageCode = 1033
        })
      }
      IsPrimaryName = $true
    }
  )
} | ConvertTo-Json -Depth 10

Invoke-RestMethod -Uri "$envUrl/api/data/v9.2/EntityDefinitions" `
  -Headers $headers -Method Post -Body $body
```

### Phase 4: Add Additional Columns

Add columns not included in the deep-insert:

```powershell
# Lookup (N:1) relationship
$relBody = @{
  SchemaName = "cr8b0_parenttable_childtable"
  "@odata.type" = "Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata"
  ReferencedEntity = "cr8b0_parenttable"
  ReferencingEntity = "cr8b0_childtable"
  Lookup = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.LookupAttributeMetadata"
    SchemaName = "cr8b0_parenttableid"
    DisplayName = @{
      "@odata.type" = "Microsoft.Dynamics.CRM.Label"
      LocalizedLabels = @(@{
        "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
        Label = "Parent Table"
        LanguageCode = 1033
      })
    }
  }
} | ConvertTo-Json -Depth 10

Invoke-RestMethod -Uri "$envUrl/api/data/v9.2/RelationshipDefinitions" `
  -Headers $headers -Method Post -Body $relBody
```

### Phase 5: Publish Customizations

```powershell
$publishBody = @{ ParameterXml = "<importexportxml><entities><entity>cr8b0_mytable</entity></entities></importexportxml>" } | ConvertTo-Json
Invoke-RestMethod -Uri "$envUrl/api/data/v9.2/PublishXml" `
  -Headers $headers -Method Post -Body $publishBody
```

### Phase 6: Output Manifest

Create `.datamodel-manifest.json` in the project root with table names, logical
names, column definitions, and relationship info for other skills to consume.

## Common Mistakes & Warnings

- **Always include `@odata.type`** on every nested object -- the Dataverse
  metadata API requires explicit type annotations.
- **SchemaName must include publisher prefix** (e.g., `cr8b0_`). Query
  `publishers` to find the correct prefix.
- **Publish after every change** -- tables and columns aren't visible until
  published via `PublishXml`.
- **Deep-insert creates table + columns in one call** -- use it for the initial
  create to avoid multiple round-trips.
- **Token expires** -- refresh if operations span more than ~60 minutes.
- **Do NOT use `pac paportal` commands** for Code Sites v2.
