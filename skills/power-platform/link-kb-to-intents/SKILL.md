---
name: power-platform-link-kb-to-intents
description: >
  Use when the user wants to "link knowledge articles to intents", "attach KB
  articles to the Customer Intent Agent", "populate the intent Knowledge articles
  tab", "map KB to intents", or "surface the right article per intent" in Dynamics
  365 Contact Center / Copilot Service. Creates the intent -> knowledge article
  associations that back the intent's "Knowledge articles" tab, via the
  msdyn_intentsolutionmap table using the Web API. Pairs with build-intents and
  knowledge-base-article.
version: 1.0.0
author: UK Dynamics SE team
tags:
  - power-platform
  - dataverse
  - contact-center
  - customer-intent-agent
  - knowledge-base
  - copilot-service
---

# Link Knowledge Articles to Customer Intent Agent Intents

> **Trigger**: "link the KB articles to the intents", "fill the intent Knowledge
> articles tab", "map each article to its intent".

Associates a **published knowledge article** with an **intent** so it appears on the
intent's **Knowledge articles** tab and can be served by the Customer Intent Agent.
The association lives in the **`msdyn_intentsolutionmap`** table (a "solution" for an
intent), written via the Dataverse Web API.

> **Prerequisites**
> - Intents already exist (see the **build-intents** skill).
> - Knowledge articles already exist and are published (see the
>   **knowledge-base-article** skill).
> - Azure CLI signed in to the environment tenant; the Web API token is minted with
>   `az account get-access-token --resource "$envUrl/"`.

## Why this table (and not an N:N)

`msdyn_intent` has **no N:N relationship** with `knowledgearticle`. The intent's
Knowledge-articles subgrid is backed by **`msdyn_intentsolutionmap`** — the only table
that joins `msdyn_intent` to `knowledgearticle` (via `msdyn_rootknowledgearticleid`).
The same table also holds other "solutions" for an intent (e.g. route to an agent
group), distinguished by `msdyn_solutiontype`.

## The record you create

Create one `msdyn_intentsolutionmap` row per intent→article link. Required/important
fields:

| Field | Value |
|---|---|
| `msdyn_intentid` (lookup) | the **leaf** intent (`msdyn_isgroup=false`) |
| `msdyn_rootknowledgearticleid` (lookup) | the **ROOT** article (`isrootarticle=true`) — **not** the published version. See the fork note below |
| `msdyn_solutiontype` (string) | `knowledgearticle` — see the gotcha below |
| `msdyn_intentfamilyid` (lookup) | the Line of Business (`msdyn_intentfamily`), e.g. "Default LOB" |
| `msdyn_intentgroupconditionid` (lookup) | **NOT NULL** — reuse the condition already tied to that intent's **parent group** |
| `msdyn_order` (int) | `1` |
| `msdyn_reviewstate` (choice) | `192350001` (Approved) |
| `msdyn_source` (choice) | `192350002` (Manually Edited) |

### Gotcha 1 — `msdyn_solutiontype` is free text; use the target table's logical name

`msdyn_solutiontype` is `NVARCHAR(100)` and accepts **any** string, so a wrong value
saves silently but the row won't render on the Knowledge-articles tab. The correct
value follows the table's own convention: it is the **logical name of the solution
target table**. Existing auto-generated rows use `msdyn_agentgroup` (+
`msdyn_agentgroupid`); a knowledge-article solution uses **`knowledgearticle`** (+
`msdyn_rootknowledgearticleid`).

### Gotcha 2 — link the ROOT article, not the published version

Publishing a knowledge article **forks it into two records**: a **root**
(`isrootarticle=true`, stays Draft) and a **published latest version**
(`isrootarticle=false`, `islatestversion=true`, `statecode=3`).
`msdyn_rootknowledgearticleid` must point at the **root** id. Fetch it with:

```
knowledgearticles?$filter=articlepublicnumber eq 'KB-XXX' and isrootarticle eq true
  &$select=knowledgearticleid
```

### Gotcha 3 — `msdyn_intentgroupconditionid` is required

Every solution map needs a group condition (`msdyn_intentgroupcondition`, which itself
requires `msdyn_condition` + `msdyn_fetchxml`). Don't fabricate one. **Reuse the
condition already attached to that intent's parent-group solution map** (the
auto-generated group routing rows). Look them up once:

```
msdyn_intentsolutionmaps?$select=_msdyn_intentid_value,_msdyn_intentgroupconditionid_value
```

Build a `parentGroupId -> conditionId` map and use the condition matching each leaf
intent's parent group.

## Procedure

1. **Discover** — list the leaf intents (`msdyn_intent`, `msdyn_isgroup=false`) with
   their `msdyn_parentgroupid`; list the published articles and their **root** ids;
   list existing group solution maps to build the parent-group → condition map.
2. **Test one** — create a single row for one intent, then read it back
   (`msdyn_rootknowledgearticleid`, `msdyn_solutiontype=knowledgearticle`, `statecode`
   Active). Confirm it renders on the intent's Knowledge articles tab before batching.
3. **Batch** — loop the rest. Make it **idempotent**: skip if a row already exists for
   the same `_msdyn_intentid_value` + `_msdyn_rootknowledgearticleid_value`.
4. **Verify** — `SELECT COUNT(...) WHERE msdyn_solutiontype = 'knowledgearticle'`
   equals the number of intents you linked.

## Create pattern (Web API)

```powershell
$envUrl = 'https://<org>.crm.dynamics.com'
$tok = az account get-access-token --resource "$envUrl/" --query accessToken -o tsv
$H = @{ Authorization = "Bearer $tok"; 'Content-Type' = 'application/json';
        'OData-MaxVersion' = '4.0'; 'OData-Version' = '4.0'; Prefer = 'return=representation' }

$body = @{
  msdyn_name         = 'Low water pressure - KB-WATER-001'
  msdyn_order        = 1
  msdyn_reviewstate  = 192350001    # Approved
  msdyn_source       = 192350002    # Manually Edited
  msdyn_solutiontype = 'knowledgearticle'
  'msdyn_intentid@odata.bind'               = "/msdyn_intents($leafIntentId)"
  'msdyn_rootknowledgearticleid@odata.bind' = "/knowledgearticles($rootArticleId)"
  'msdyn_intentfamilyid@odata.bind'         = "/msdyn_intentfamilies($lobId)"
  'msdyn_intentgroupconditionid@odata.bind' = "/msdyn_intentgroupconditions($conditionId)"
} | ConvertTo-Json
Invoke-RestMethod -Uri "$envUrl/api/data/v9.2/msdyn_intentsolutionmaps" -Headers $H -Method Post -Body $body
```

> **See the actual error.** In PowerShell 7, wrap calls in
> `try { ... } catch { Write-Host $_.ErrorDetails.Message }` — otherwise you only get
> a generic `400 (Bad Request)` instead of the OData reason.

## Common Mistakes & Warnings

- **Wrong `msdyn_solutiontype`** — accepts any string but must be `knowledgearticle`,
  or the row saves and is invisible on the tab.
- **Linking the published version instead of the root** — use `isrootarticle=true`.
- **Missing `msdyn_intentgroupconditionid`** — it's NOT NULL; reuse the parent group's
  existing condition rather than creating one.
- **Group intents** — link leaf intents (`msdyn_isgroup=false`), not group rows.
- **Not idempotent** — filter on intent + root-article before inserting to avoid
  duplicate solution rows.
- **Dataverse MCP vs Web API** — the MCP `create_record` works for this table, but the
  Web API script is easier to make idempotent and batch.

## Related skills

- **build-intents** — create the intent groups + leaf intents first.
- **knowledge-base-article** — create and publish the articles first (and the
  publish-fork behaviour that dictates using the root id).
