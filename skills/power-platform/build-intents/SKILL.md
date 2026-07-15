---
name: power-platform-build-intents
description: >
  Use when the user wants to "add intents", "build intents", "set up the Customer
  Intent Agent", "create an intent library", "populate intents for a demo",
  "add intent groups", or "make intents for the voice/chat agent" in Dynamics 365
  Contact Center / Copilot Service. Interview-driven and beginner-friendly: the
  agent ASKS what intents the customer wants (never assumes a taxonomy), then
  builds intent groups + intents + a follow-up question on each, all via the
  Dataverse MCP. Optimised for PRE-SALES demos.
version: 1.0.0
author: UK Dynamics SE team
tags:
  - power-platform
  - dataverse
  - contact-center
  - customer-intent-agent
  - copilot-service
  - pre-sales
---

# Build Intents for the Customer Intent Agent

> **Trigger**: "add some intents", "build an intent library", "set up the Customer
> Intent Agent for the demo", "create intent groups and intents".

This skill populates the **Customer Intent Agent** in Dynamics 365 Contact Center /
Copilot Service with a clean, demo-ready set of **intent groups** and **intents**,
each with at least one **follow-up question**. It is built for **pre-sales**: the
goal is a tidy, believable, easy-to-explain intent library that makes the demo flow.

The agent does everything through the **Dataverse MCP** (introspect → create →
verify). It **interviews the user first** — it never assumes what the intents should
be — then builds groups, intents, and attributes, and finishes with the one manual
step (assigning **All Users**) that can't be done safely via the API.

> **For users new to Dynamics 365:** you don't need to know table names, GUIDs, or
> option-set codes. Answer a few plain questions and the agent builds it all,
> narrating each step.

## Plain-language glossary

- **Customer Intent Agent** — the feature that works out *why* a customer is
  contacting you (their "intent") and helps the agent/self-service respond.
- **Intent** — one reason a customer gets in touch, e.g. "No water". Written in plain
  English. It carries a sample **caller phrase** (what the customer actually says).
- **Intent group** — a folder that holds related intents, e.g. "Water Quality".
- **Attribute** — a follow-up question the agent asks to pin down the issue, e.g.
  "What's your postcode?". This skill puts **at least one on every intent**.
- **Line of business (LOB)** — the top-level partition intents live under. Most demo
  orgs have a single one called **Default LOB** — just reuse it.
- **User groups / "All Users"** — which reps an intent group is routed to. For demos
  we set **All Users** on every group (see Rule 2 + Step 6).
- **Self-service (autonomous support)** — if ON, the front-door bot can try to handle
  the intent itself for deflection. Turn OFF for sensitive/assisted-only intents.

---

## The four pre-sales rules (non-negotiable defaults)

1. **ASK — never assume a taxonomy.** The customer may **not** use disposition codes
   (most won't). Do **not** invent a taxonomy or copy one from another engagement.
   Interview them (Step 0) and build exactly what they ask for. Only *offer*
   disposition codes as one possible source **if they say they have them**.
2. **All Users by default.** Every active intent group must be assigned the **All
   Users** user group so it demos cleanly and nothing looks half-configured
   (Step 6). This is a pre-sales default; in production you'd assign specialist
   teams instead.
3. **Plain English everywhere.** Intent group names and intent names must be simple,
   human, jargon-free (e.g. "No water", not "SUPPLY_INT_L1"). The caller phrase
   should sound like a real person.
4. **At least one attribute per intent.** Every intent gets one relevant follow-up
   question so the demo can show the agent gathering information (Step 5).

---

## Prerequisites

- **Customer Intent Agent is turned on** (Copilot Service admin center → *Customer
  support* → **Intent** → *Turn on Customer Intent Agent*). Needs a pay-as-you-go
  plan + the **Intent Manager** and **CSR Manager** roles.
- **Dataverse MCP** connected to the target environment (`mcp_microsoft_dat_*`).
- You can reach the **Copilot Service admin center** in a browser for the one manual
  step (assigning All Users).

---

## Step 0 — Interview the user (do this first, always)

Keep it short and plain. Capture answers before creating anything.

1. **What is this for?** Confirm it's a demo and the channel focus (voice, chat,
   both). This shapes which intents matter and self-service on/off.
2. **What intents do you want?** Ask them to list the reasons customers contact them,
   in their own words. Prompt gently if they're unsure:
   > "Think about the top handful of reasons people phone in. What are they?"
   Offer to group them, but let *them* name things.
3. **Do you already have a list to reuse?** Only *if they volunteer it*: disposition
   codes, an IVR menu, a call-reason report, a website "report a problem" list, or a
   knowledge-base structure. Use it as the source. **If they have none, that's normal
   — build from the plain-English list in step 2.**
4. **How should they be grouped?** Propose a small number (3–6) of plain-English
   **intent groups**, each holding a few intents. Confirm names with the user.
5. **Anything sensitive/assisted-only?** (e.g. bereavement, vulnerability, financial
   hardship, complaints.) Those get **self-service OFF**; everything else ON.
6. **Play it back.** Show a simple table — *Group → Intent → sample caller phrase* —
   and get a thumbs-up **before** you create records.

> Output of Step 0 = an agreed list of groups, intents (plain-English names), a
> sample caller phrase for each, and which are assisted-only. Do not proceed without it.

---

## How the system is structured (technical reference)

Everything lives in **three tables**, all reachable via the Dataverse MCP.

### Table 1 — `msdyn_intent` (holds BOTH groups and intents)

The same table stores intent **groups** and the **intents** inside them; a flag
separates them and a lookup links a child to its group.

| Column (logical) | Type | Meaning |
|---|---|---|
| `msdyn_name` | string(100) | Display name shown in the *Intents* list |
| `msdyn_intentstring` | multiline (NOT NULL) | The natural-language phrase / sample caller utterance |
| `msdyn_isgroup` | bool (NOT NULL) | **true = intent group**, false = leaf intent |
| `msdyn_parentgroupid` | lookup → `msdyn_intent` | The child intent's group (null on groups) |
| `msdyn_intentfamilyid` | lookup → `msdyn_intentfamily` (NOT NULL) | **Line of business** (partition) |
| `msdyn_is_selfserve_enabled` | bool | "Autonomous support / Self-service" toggle |
| `msdyn_description` | string(4000) | Optional description |
| `msdyn_reviewstate` | choice (NOT NULL) | Pending `192350000` / **Approved `192350001`** / Discarded `192350002` |
| `msdyn_reviewstatesource` | choice | AI Generated `192350000` / **Admin Updated `192350002`** |
| `msdyn_harvestingsource` | choice (NOT NULL) | Data Execution Run `192350000` / Simulation `192350001` / **Manually Edited `192350002`** |
| `msdyn_intentvolume`, `msdyn_occurrencecount*` | int | Analytics (leave null for hand-built) |

### Table 2 — `msdyn_intentattribute` (the follow-up question / data point)

| Column | Type | Meaning |
|---|---|---|
| `msdyn_name` | string(100) (NOT NULL) | The data point, e.g. "Property postcode". Short — the agent forms the question from it |
| `msdyn_intentfamilyid` | lookup → `msdyn_intentfamily` (NOT NULL) | Same LOB |
| `msdyn_reviewstate` | choice (NOT NULL) | Use **Approved `192350001`** |
| `msdyn_source` | choice (NOT NULL) | Use **Manually Edited `192350002`** |

### Table 3 — `msdyn_intentattributeset` (junction linking an attribute to an intent)

| Column | Type | Meaning |
|---|---|---|
| `msdyn_intentid` | lookup → `msdyn_intent` (NOT NULL) | The intent |
| `msdyn_intentattributeid` | lookup → `msdyn_intentattribute` (NOT NULL) | The attribute |
| `msdyn_intentfamilyid` | lookup → `msdyn_intentfamily` (NOT NULL) | Same LOB |
| `msdyn_ismandatory` | bool (NOT NULL) | Whether the agent must collect it |
| `msdyn_reviewstate` / `msdyn_source` | choice (NOT NULL) | Approved `192350001` / Manually Edited `192350002` |

### Line of business (LOB)

- Intents and attributes **require** an LOB lookup (`msdyn_intentfamilyid`).
- Find it: `SELECT msdyn_intentfamilyid, msdyn_name FROM msdyn_intentfamily`. Most
  demo orgs have exactly one, **Default LOB** — reuse its GUID for everything.

### Mental model

```
msdyn_intentfamily  (Line of business, e.g. "Default LOB")
└── msdyn_intent  (isgroup=true)            ← intent GROUP, e.g. "Water Quality"
    └── msdyn_intent  (isgroup=false, parentgroupid → group)   ← INTENT, e.g. "No water"
        └── msdyn_intentattributeset  →  msdyn_intentattribute ← follow-up question
```

---

## ⚠️ The one gotcha that will bite you

**A plugin auto-overwrites `msdyn_name` with `msdyn_intentstring` on every create AND
update of `msdyn_intent`.** So if you create an intent with a short name *and* a
different caller phrase in one call, the name comes back as the phrase.

**Fix — always two steps for leaf intents:**
1. **Create** the intent with `msdyn_intentstring` = the sample caller phrase.
2. **Update** it sending **only** `msdyn_name` = the short plain-English label
   (do **not** include `msdyn_intentstring` in that second call).

Groups are unaffected because their name and phrase are the same word anyway.

---

## Step-by-Step Procedure

### Phase 1 — Confirm the Line of business
Run `SELECT msdyn_intentfamilyid, msdyn_name FROM msdyn_intentfamily`. Reuse the
single **Default LOB** GUID (call it `<LOB>` below). Only create a new LOB if the
customer explicitly wants separate partitions.

### Phase 2 — Create the intent groups (plain English, Rule 3)
For **each** agreed group, `create_record` on `msdyn_intent`:
```jsonc
{
  "msdyn_name": "Water Quality",           // plain English
  "msdyn_intentstring": "Water Quality",    // same as name for groups
  "msdyn_isgroup": true,
  "msdyn_intentfamilyid": { "relatedTable": "msdyn_intentfamily", "recordId": "<LOB>" },
  "msdyn_reviewstate": 192350001,           // Approved
  "msdyn_reviewstatesource": 192350002,     // Admin Updated
  "msdyn_harvestingsource": 192350002,      // Manually Edited
  "msdyn_is_selfserve_enabled": true
}
```
Keep the returned **group GUID** for its children.

### Phase 3 — Create the intents (two-step name, Rule 3)
For **each** intent, first `create_record`:
```jsonc
{
  "msdyn_intentstring": "I've got no water at all coming out of my taps",  // caller phrase
  "msdyn_isgroup": false,
  "msdyn_parentgroupid": { "relatedTable": "msdyn_intent", "recordId": "<groupGUID>" },
  "msdyn_intentfamilyid": { "relatedTable": "msdyn_intentfamily", "recordId": "<LOB>" },
  "msdyn_reviewstate": 192350001,
  "msdyn_reviewstatesource": 192350002,
  "msdyn_harvestingsource": 192350002,
  "msdyn_is_selfserve_enabled": true          // false for assisted-only intents
}
```
Then **`update_record`** on the new intent with **only** the label:
```jsonc
{ "msdyn_name": "No water" }
```

### Phase 4 — Add at least one attribute to EVERY intent (Rule 4)
No intent ships without a follow-up question. For each intent:
1. `create_record` on `msdyn_intentattribute` (the data point):
   ```jsonc
   { "msdyn_name": "Property postcode",
     "msdyn_intentfamilyid": { "relatedTable": "msdyn_intentfamily", "recordId": "<LOB>" },
     "msdyn_reviewstate": 192350001, "msdyn_source": 192350002 }
   ```
2. `create_record` on `msdyn_intentattributeset` (link it to the intent):
   ```jsonc
   { "msdyn_intentid": { "relatedTable": "msdyn_intent", "recordId": "<intentGUID>" },
     "msdyn_intentattributeid": { "relatedTable": "msdyn_intentattribute", "recordId": "<attrGUID>" },
     "msdyn_intentfamilyid": { "relatedTable": "msdyn_intentfamily", "recordId": "<LOB>" },
     "msdyn_ismandatory": true,
     "msdyn_reviewstate": 192350001, "msdyn_source": 192350002 }
   ```
Pick a **relevant** question per intent (postcode/date/meter for a move; location/
danger for a burst; account reference for billing). Reuse an attribute across intents
by creating just a new junction row.

### Phase 5 — Assign "All Users" to every group (Rule 2) — MANUAL, supported step
This is the **only** part that can't be done safely via the API. The intent-group ↔
user-group assignment is undocumented unified-routing config; the `msdyn_intent`
record has no user-group column and hand-writing the intersect risks misconfiguring
routing. Do it in the UI:

> **Copilot Service admin center → Customer support → Intent → Manage intent groups**
> → tick the new groups → toolbar **Assign user groups** → **All Users** → Save.

You can select **all groups at once**. Either drive it via browser automation or hand
the 2 clicks to the user, then confirm. (Badge shows immediately; routing reflects in
~30 min per the page banner.)

### Phase 6 — Housekeeping (optional)
- **Discard** any leftover/non-relevant intents or groups so the demo list is clean:
  `update_record` → `msdyn_reviewstate = 192350002` (Discarded). Don't delete.
- Existing AI-discovered groups can be reused — just add your intents under them.

### Phase 7 — Verify
Dataverse SQL (this MCP caps results at **TOP 20** — page if you have more):
```sql
SELECT g.msdyn_name AS grp, i.msdyn_name AS nm, i.msdyn_intentstring AS phrase
FROM msdyn_intent i JOIN msdyn_intent g ON i.msdyn_parentgroupid = g.msdyn_intentid
WHERE i.msdyn_isgroup = 0 AND i.msdyn_reviewstate = 192350001
ORDER BY g.msdyn_name, i.msdyn_name
```
Confirm: every intent has a plain-English `nm` (not the phrase), a sensible `phrase`,
sits under the right group, and has ≥1 attribute. Then check the **Manage intent
groups** list shows **All Users** on every active group.

### Phase 8 — Make them usable (optional, tell the user)
- **Use in AI agent:** *Manage intents* → select approved intents → **Use in AI
  agent** (bulk) to expose them to a Copilot voice/chat agent.
- **Knowledge articles:** open an intent → *Knowledge articles* tab → **Add** to link
  KB content the agent can answer from.

### Phase 9 — Present the review table (ALWAYS do this at the end)
Whenever this skill is used, finish by showing the user a **review table** built from
the live data (Phase 7 query + attributes), using **exactly these four columns**:

| Category (group) | Intent | Sensible question (caller utterance) | Attribute |
|---|---|---|---|

- One row per intent, grouped by category. If an intent has multiple attributes,
  list them all in the Attribute cell (comma-separated) or add extra rows.
- "Sensible question (caller utterance)" = the intent's `msdyn_intentstring`.
- Pull the Attribute column by joining `msdyn_intentattributeset` →
  `msdyn_intentattribute` for each intent.
- End with a one-line confirmation that every intent has ≥1 attribute (Rule 4) and
  every group is set to All Users (Rule 2). This table is the sign-off artefact.

---

## Common Mistakes & Warnings

- **Name comes back as the caller phrase** — you set name + intentstring in one call.
  Fix: two-step (create with phrase → update with name only). See the gotcha above.
- **Assuming a taxonomy** — never reuse disposition codes / another customer's list
  unless *this* customer says they use it. Interview first (Rule 1).
- **Jargon names** — "SUP_INT" instead of "No water". Keep names plain (Rule 3).
- **An intent with no attribute** — breaks Rule 4; every intent needs ≥1 question.
- **Trying to set "All Users" via the API** — it's undocumented routing config; do it
  in the admin center (Phase 5). Don't hand-write intersect rows.
- **Choice values as labels** — choice columns take the **numeric** option value
  (e.g. `192350001`), not the text.
- **Missing required lookups** — `msdyn_intentfamilyid` is required on intents *and*
  attributes *and* junctions; leaf intents also need `msdyn_parentgroupid`.
- **Query returns nothing / errors on TOP** — this MCP allows a max of **20** rows;
  add/keep `TOP 20`.
- **Deleting instead of discarding** — set `msdyn_reviewstate = 192350002` to hide;
  deleting can break references.

## Key Takeaway

> Interview first (never assume a taxonomy), build plain-English **groups → intents →
> one follow-up question each**, remember the **name = intentstring auto-overwrite**
> (two-step create), set **All Users** in the admin center, and everything is just
> three tables: `msdyn_intent` (groups + intents), `msdyn_intentattribute`, and the
> `msdyn_intentattributeset` junction — all under a Line of business. **Always finish
> by presenting the four-column review table (Phase 9) for user sign-off.**
