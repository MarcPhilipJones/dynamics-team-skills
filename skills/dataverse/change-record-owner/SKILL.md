---
name: change-record-owner
description: >
  Use when the user asks to "change record owner", "assign to team",
  "set ownership via Logic App", or "assign record to a team from Power Pages".
version: 1.0.0
author: Marc
tags:
  - dataverse
  - logic-app
  - ownership
  - security-roles
---

# Change Dataverse Record Owner via Logic App

## Context
Power Pages `/_api/` cannot set `ownerid@odata.bind` to a team — it returns a permission error.
The workaround is to use a server-side mechanism (Logic App, Power Automate, or plugin) to assign ownership.

## Method: Dataverse Connector in Logic App (Confirmed Working)

### Logic App PATCH Body
Use `_ownerid_value` + `_ownerid_type` fields in the Dataverse connector's Update action:

```json
{
  "_ownerid_value": "<team-guid>",
  "_ownerid_type": "teams"
}
```

For user assignment, use `_ownerid_type`: `systemusers`.

### Direct Web API (Method 2 — Also Works)
If the Dataverse connector fails, use an HTTP action with OAuth:

```http
PATCH /api/data/v9.2/opportunities(<id>)
Content-Type: application/json

{ "ownerid@odata.bind": "/teams(<team-guid>)" }
```

## Critical: Security Role Prerequisites

When assigning a record to a team, Dataverse checks that the **target team** has sufficient privileges
on ALL cascaded entities, not just the primary table.

### Common Error
```
Principal team (Id=...) is missing prvReadActionCard privilege on entity 'actioncard'
```

### Fix
Add the missing privilege to the team's security role via the Web API:

```powershell
$body = @{
  Privileges = @(@{ PrivilegeId = "<privilege-guid>"; Depth = "1" })
} | ConvertTo-Json -Depth 5

$uri = "$orgUrl/api/data/v9.2/roles($rootRoleId)/Microsoft.Dynamics.CRM.AddPrivilegesRole"
Invoke-RestMethod -Uri $uri -Method POST -Headers $h -Body ([System.Text.Encoding]::UTF8.GetBytes($body))
```

**Key:** Use the **root role ID** (`_parentrootroleid_value`), not the team's instance role ID.

### Commonly Missing Privilege (real-world example)
- **Missing Privilege:** `prvReadActionCard`
- **PrivilegeId:** `41bc4dd7-920d-48a5-81ad-356d3c935b71`
- **Depth:** 1 (Basic/User level)

The Action Card table is auto-related to most entities, so cascade-assign on
nearly any record will trip this if your custom role doesn't grant it.

## Logic App Pattern: Conditional Team Assignment

```
Trigger: HTTP POST { recordId, partnerAccountId, setOwnerToPartner }
  ↓
Set Currency → Set Price List (or other per-record bootstrap)
  ↓
IF setOwnerToPartner == true:
  IF partnerAccountId == regionAAccountId  → Set Owner to Region A Team
  ELIF partnerAccountId == regionBAccountId → Set Owner to Region B Team
  ELSE → Set Owner to HQ Team
ELSE:
  Set Owner to HQ Team (default)
  ↓
Response 200
```

## Gotchas & Lessons Learned

1. **Dataverse connector `_ownerid_type`** accepts `teams` (plural) — not `team`.
2. **`AssignRequest`** is deprecated — use PATCH with `ownerid@odata.bind` or `_ownerid_value`.
3. **Cascade assign** checks ALL related entity privileges on the target team — not just the primary table.
4. **`prvReadActionCard`** is commonly missing from custom roles — the Action Card table is auto-related to most entities.
5. **Logic App trigger URL persists** across PUT updates — the SAS token doesn't change when redeploying.
6. **Test with a dedicated test Logic App first** — avoids breaking production while debugging privilege issues.

## Key Takeaway
The Dataverse connector in Logic Apps CAN assign ownership to teams using `_ownerid_value` + `_ownerid_type: "teams"`.
The main blocker is usually missing security role privileges on the target team, not the connector itself.
