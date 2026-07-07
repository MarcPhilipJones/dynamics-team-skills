---
name: power-platform-flows-via-web-api
description: >
  Use when you need to "create a Power Automate flow via API", "build a cloud flow
  with a script", "POST /workflows", or when an API-created flow "won't open in the
  designer", the trigger fires on the wrong change type, or edits don't take effect.
  Covers creating Dataverse-triggered cloud flows programmatically and the gotchas.
version: 1.1.0
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
exact payload shape and the gotchas that otherwise cost hours.

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
  `item/<col>`, lookups via `item/<Nav>@odata.bind = /leads(<guid>)`.

## Common Mistakes & Warnings

- **Trigger change-type codes (VERIFIED):** `subscriptionRequest/message` = **1 Added,
  2 Deleted, 3 Added or Modified, 4 Added/Modified/Deleted** — NOT 1=Create/2=Update.
  Using `2` for a "modified" trigger silently makes it fire on **Deleted**.
- **`clientdata` needs a top-level `schemaVersion`** — omitting it returns
  `0x80060468 "Flow clientdata is in invalid format … Required property 'schemaVersion' not found"`.
  Shape is `{"properties": {...}, "schemaVersion": "1.0.0.0"}`.
- **Trigger conditions (skip unwanted rows):** add `"conditions": [{"expression": "@..."}]`
  to the trigger to gate it (e.g. skip a channel). Compare as string and treat null/blank:
  `@not(equals(string(triggerOutputs()?['body/<prefix>_field']), '<code>'))` — a blank field
  then still fires (good for back-compat). Re-register OFF/ON in the portal after adding.
- **Designer won't open ("Required property '$schema' not found. Path ''")** — raw-API
  flows omit `metadata.operationMetadataId` on each trigger/action. Add a GUID
  `metadata.operationMetadataId` to every operation (recurse into `If`/`else`/`actions`)
  and set `definition.outputs:{}`. Native flows always have it.
- **Edits don't take effect on an activated flow** — a raw `clientdata` PATCH (or an API
  statecode toggle) does **not** re-register the trigger webhook. **Turn the flow OFF then
  ON in the portal** to pick up trigger/definition changes.
- **⚠️ An API statecode toggle (0→1) DE-REGISTERS a webhook flow** — for Dataverse-triggered
  (`OpenApiConnectionWebhook`) flows, deactivating/reactivating via the Web API drops the
  callback and the flow then **silently never fires** (confirmed: a guarded create-trigger
  flow stopped advancing test rows after an API toggle). Only the **portal** OFF/ON
  re-registers the webhook. So: after ANY API edit to a webhook flow, portal-toggle it.
- **Skills / Request-trigger flows are different** — agent-callable flows use a synchronous
  `Request`/`Skills` trigger (no webhook), so **API create + `statecode` activate works
  fine** and edits apply without a portal toggle.
- **Owner assignment to a team fails** — the lookup bind needs a **leading slash**
  (`/teams(<guid>)`), AND the **team must have a security role** to own records.
- **Copilot-callable (PowerVirtualAgents / Request-kind) flows CANNOT be *hand-built* via raw
  API** — a from-scratch definition never registers (open fails; PATCH → "missing required
  field 'definition'"). **BUT cloning a *known-good* Skills flow works:** GET an existing
  working agent-callable flow's `clientdata`, modify its inputs/actions, and `POST /workflows`
  — it creates + activates fine (proven building a batch write-back flow from a working
  capture flow). Keep every action's `operationMetadataId` + the top-level `schemaVersion`.
- **AI Builder prompt inside a flow** — the "Run a prompt" action is
  `operationId: aibuilderpredict_customprompt`, `apiId: providers/Microsoft.ProcessSimple/operationGroups/aibuilder`,
  and **reuses the Dataverse connection** (no new connector). Inputs `item/requestv2/<x>`;
  output text at `body('Run_a_prompt')?['responsev2']?['predictionOutput']?['text']`. See
  `power-platform/ai-builder-prompt-in-flow`.
- `&` in an OData `$filter` name breaks the URL — encode it or fetch+match client-side.

## Key Takeaway

> Standard automated flows POST fine to `/workflows` — but get the `message` change-type
> right (3 = Added or Modified), add `operationMetadataId`, toggle OFF/ON in the portal to
> apply edits, and build agent-callable flows in the designer, not via API.
