---
name: power-platform-flows-via-web-api
description: >
  Use when you need to "create a Power Automate flow via API", "build a cloud flow
  with a script", "POST /workflows", or when an API-created flow "won't open in the
  designer", the trigger fires on the wrong change type, or edits don't take effect.
  Covers creating Dataverse-triggered cloud flows programmatically and the gotchas.
version: 1.0.0
author: Jamie Barker
tags:
  - power-platform
  - power-automate
  - dataverse
  - web-api
  - flows
---

# Create Power Automate cloud flows via the Dataverse Web API

> **Trigger**: "create a flow via API" / "flow won't open in the designer" / "trigger
> fires on the wrong change type"

Standard **automated** cloud flows (Dataverse row triggers) can be created head-less via
`POST /workflows`, which is invaluable for scripted demo builds. This skill captures the
exact payload shape and the four gotchas that otherwise cost hours.

## Prerequisites

- Auth to Dataverse (token + `MSCRM.SolutionUniqueName` header to add to a solution).
- A **connection reference** for the Dataverse connector (`shared_commondataserviceforapps`).

## Step-by-Step Procedure

### 1. Build `clientdata` (exact shape)

```json
{ "schemaVersion": "1.0.0.0",
  "properties": {
    "connectionReferences": { "shared_commondataserviceforapps": {
        "runtimeSource": "embedded",
        "connection": { "connectionReferenceLogicalName": "<prefix_connref>" },
        "api": { "name": "shared_commondataserviceforapps" } } },
    "definition": {
      "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
      "contentVersion": "1.0.0.0",
      "parameters": { "$connections": {"defaultValue":{},"type":"Object"},
                      "$authentication": {"defaultValue":{},"type":"SecureObject"} },
      "triggers": { ... }, "actions": { ... }, "outputs": {} } } }
```

### 2. POST the workflow

`POST /api/data/v9.2/workflows` with header `MSCRM.SolutionUniqueName=<solution>` and body:
`{ name, description, category:5, type:1, primaryentity:"none", statecode:0, clientdata:"<json string>" }`

### 3. Trigger + action operations

- Trigger: `OpenApiConnectionWebhook`, `operationId: SubscribeWebhookTrigger`, params
  `subscriptionRequest/message`, `/entityname`, `/scope` (4=Org), optional
  `/filteringattributes` and `/filterexpression`.
- Actions: `OpenApiConnection` with operationId `CreateRecord` / `UpdateRecord` /
  `GetItem` / `PerformUnboundAction`; params `entityName` (plural set), `recordId`,
  `item/<col>`, lookups via `item/<Nav>@odata.bind = /<entityset>(<guid>)`.

## Common Mistakes & Warnings

- **Trigger change-type codes (VERIFIED):** `subscriptionRequest/message` = **1 Added,
  2 Deleted, 3 Added or Modified, 4 Added/Modified/Deleted** — NOT 1=Create/2=Update.
  Using `2` for a "modified" trigger silently makes it fire on **Deleted**.
- **Designer won't open ("Required property '$schema' not found. Path ''")** — raw-API
  flows omit `metadata.operationMetadataId` on each trigger/action. Add a GUID
  `metadata.operationMetadataId` to every operation (recurse into `If`/`else`/`actions`)
  and set `definition.outputs:{}`. Native flows always have it.
- **Edits don't take effect on an activated flow** — a raw `clientdata` PATCH (or an API
  statecode toggle) does **not** re-register the trigger webhook. **Turn the flow OFF then
  ON in the portal** to pick up trigger/definition changes.
- **Owner assignment to a team fails** — the lookup bind needs a **leading slash**
  (`/teams(<guid>)`), AND the **team must have a security role** to own records.
- **Copilot-callable (PowerVirtualAgents / Request-kind) flows CANNOT be created via raw
  API** — they never register with the Flow service (open fails; PATCH -> "missing required
  field 'definition'"). Build those in the **Agent flows designer** instead.
- `&` in an OData `$filter` name breaks the URL — encode it or fetch+match client-side.

## Key Takeaway

> Standard automated flows POST fine to `/workflows` — but get the `message` change-type
> right (3 = Added or Modified), add `operationMetadataId`, toggle OFF/ON in the portal to
> apply edits, and build agent-callable flows in the designer, not via API.
