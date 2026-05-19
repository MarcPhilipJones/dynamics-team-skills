---
name: copilot-studio-voice-agent
description: >
  Runbook for building, debugging and iterating on Realtime Voice Copilot Studio
  agents (generative orchestration, speech-to-speech) integrated with Dynamics 365
  Contact Center. Use when escalation doesn't fire, toast doesn't appear for the
  human agent, the GPT speaks when it should yield to a topic (or vice versa), a
  topic doesn't trigger on an expected phrase, or an MCP/tool call inside the
  agent silently fails.
version: 1.0.0
author: Marc
tags:
  - copilot-studio
  - voice-agent
  - realtime
  - dynamics-365-contact-center
  - escalation
  - debugging
---

# Copilot Studio Voice Agent — Debug & Iterate

Runbook for building, debugging and iterating on **Realtime Voice** Copilot Studio
agents (generative orchestration, speech-to-speech) integrated with Dynamics 365
Contact Center.

Use this skill whenever the user is working on a voice agent and reports:
- Escalation / human handoff doesn't fire
- Toast never appears for the human agent
- The GPT speaks when it should yield to a topic, or vice versa
- A topic doesn't trigger on a phrase you expected
- A Dataverse MCP tool call inside the agent silently fails

---

## 1. Mental model

| Layer | What it does | Where it lives |
|---|---|---|
| **Generative orchestrator** | Decides per-turn whether to invoke a topic, call a tool/action, or generate speech via the GPT instructions | `botcomponent.componenttype = 15` (`*.gpt.default`) |
| **System / custom topics** | Deterministic flows (e.g. Escalate, Greeting, On Error). YAML `kind: AdaptiveDialog` | `botcomponent.componenttype = 9` |
| **IVR / voice settings** | Voice font, speaking speed, latency message | `botcomponent.componenttype = 18` (`*.settings.Ivr`) |
| **Tools / actions** | Connectors, MCP servers, Power Automate flows the orchestrator can call | `botcomponent` (other types) + connection references |
| **Channel binding** | The voice workstream + queue in Dynamics 365 Contact Center | `msdyn_liveworkstream`, `msdyn_omnichannelqueue`, agent presence |

**Key insight**: The orchestrator can only invoke a topic if (a) the topic's `triggerQueries`
match the user's utterance OR (b) `intent.includeInOnSelectIntent: true` AND the GPT
instructions explicitly direct the model to invoke it.

The realtime model **cannot truly stay silent** — if it doesn't call a topic/tool it
will generate speech. So GPT instructions must always say *what* to do, not *what not* to do.

---

## 2. Three-way decomposition for any failure

When something goes wrong, identify which layer failed BEFORE editing anything:

### a. Orchestrator chose the wrong action
- **Symptom**: GPT speaks something generic when a topic should have fired.
- **Check**: `msdyn_ocliveworkitem.msdyn_transfercount` / `msdyn_escalationcount` (0 = topic didn't fire).
- **Check**: Open Copilot Studio Test pane with **Trace** on.
- **Fix**: Expand topic `triggerQueries`, set `includeInOnSelectIntent: true`, rewrite GPT instructions to explicitly invoke the topic.

> **Note for voice (May 2026 correction)**: `msdyn_transfercount` and
> `msdyn_escalationcount` are **classic-chat counters and do NOT increment
> for voice escalations** — they stay at 0 even on a successful voice handoff.
> For voice agents, verify escalation via:
> 1. A chained second `msdyn_ocsession` with `msdyn_sessioncreationreason = 192350024` (Consult/Transfer)
> 2. `_msdyn_activeagentid_value` flipped from the bot user to a real `systemuser`
> 3. Transcript `SessionInfo` with `outcome=HandOff` and `outcomeReason=AgentTransferConfiguredByAuthor`

### b. Routing sent it to the wrong queue / no queue
- **Symptom**: Topic fired but conversation sits in queue forever.
- **Check**: `msdyn_ocliveworkitem.msdyn_cdsqueueid` → confirm it's the queue you expect.
- **Check**: `msdyn_workstreamworkdistributionmode` (Push = auto-assign, Pick = manual).
- **Fix**: Workstream routing rules in Customer Service admin centre.

### c. Human agent unavailable / no capacity
- **Symptom**: Conversation routed correctly but no toast.
- **Check**: Customer Service workspace presence indicator (top-right) = green Available.
- **Check**: User has a capacity profile that includes Voice channel with `capacity > 0`.
- **Fix**: Customer Service admin centre → User management → assign capacity profile.

---

## 3. The verification query (memorise this)

```powershell
$envUrl = "https://<your-org>.crm.dynamics.com"
$tok = az account get-access-token --resource $envUrl --query accessToken -o tsv
$h = @{Authorization="Bearer $tok"; Accept="application/json"}
(Invoke-RestMethod -Uri "$envUrl/api/data/v9.2/msdyn_ocliveworkitems?`$select=msdyn_title,msdyn_transfercount,msdyn_escalationcount,_msdyn_activeagentid_value,msdyn_statuschangereason,_msdyn_cdsqueueid_value&`$orderby=modifiedon desc&`$top=1" -Headers $h).value
```

Interpret the result:

| Field | Healthy after escalation | Unhealthy |
|---|---|---|
| `msdyn_transfercount` | ≥ 1 (classic chat only) | 0 — but see voice note above |
| `msdyn_escalationcount` | ≥ 1 (classic chat only) | 0 — but see voice note above |
| `_msdyn_activeagentid_value` | human user GUID | bot user GUID → not reassigned |
| `msdyn_statuschangereason` | `AssignedBySupervisor` / `InConversation` / `AwaitingAgentAcceptance` | `CustomerDisconnectedOrLeftActiveConversation` → caller hung up before assignment |
| `_msdyn_cdsqueueid_value` | the queue you expected | wrong queue → routing rule problem |

---

## 4. Editing topics & GPT instructions via Dataverse MCP

Both live in `botcomponent.data` as YAML strings.

### Find the bot and its components
```sql
SELECT botid, name, schemaname FROM bot WHERE name LIKE '%Voice%'
SELECT name, schemaname, componenttype, botcomponentid
FROM botcomponent WHERE parentbotid = '<botid>'
```

### Read a topic
`mcp_dataverse_fetch` with id `botcomponent/<botcomponentid>` → look at the `data` attribute.

### Update a topic / GPT instructions
`mcp_dataverse_update_record` on `botcomponent`, item `{"data": "<full YAML as escaped string>"}`.

### CRITICAL — Publish after every change
Dataverse updates the **draft**. Until the user clicks **Publish** in Copilot Studio
(or runs `pac copilot publish`), the changes are invisible at runtime. ALWAYS remind
the user to publish.

---

## 5. Topic YAML — patterns that work

### Escalate topic (system) — make it orchestrator-callable
```yaml
kind: AdaptiveDialog
startBehavior: CancelOtherTopics
beginDialog:
  kind: OnEscalate
  id: main
  intent:
    displayName: Escalate
    includeInOnSelectIntent: true   # <-- CRITICAL — lets orchestrator pick it
    triggerQueries:
      - Speak to a human
      - Speak to a person
      - Speak to an agent
      # ... 40+ semantic variants
  actions:
    - kind: SendActivity
      conversationOutcome: Escalated
      activity: Escalating to a customer service representative. Please wait.
    - kind: TransferConversationV2
      transferType:
        kind: TransferToAgent
        messageToAgent: Transferring.
        context:
          kind: AutomaticTransferContext
```

The OOTB Escalate topic ships with "Talk to a human" but **not** "Speak to a human" —
add aggressive coverage including "speak to / talk to / connect me to / put me through to / transfer me to … a person / human / agent / representative / manager / someone".

### GPT instructions — explicit, not negative
**Bad** (won't work):
> "If the caller asks for a human, stay silent."

**Good** (works):
> "When the caller asks for a human, you MUST invoke the 'Escalate' topic and produce
> NO spoken output. Do not acknowledge. Do not say 'I'll transfer you'. Any spoken
> reply on an escalation request is a FAILURE — only the Escalate topic should respond."

Always include the trigger phrases inline so the model recognises them.

---

## 6. Diagnostic queries cheat sheet

```sql
-- Most recent conversation
SELECT TOP 1 msdyn_title, msdyn_transfercount, msdyn_escalationcount,
       msdyn_activeagentid, msdyn_statuschangereason, msdyn_channel,
       msdyn_cdsqueueid, msdyn_workstreamworkdistributionmode, modifiedon
FROM msdyn_ocliveworkitem
ORDER BY modifiedon DESC

-- Active conversations on a specific queue
SELECT msdyn_title, msdyn_activeagentid, msdyn_statuschangereason, modifiedon
FROM msdyn_ocliveworkitem
WHERE msdyn_cdsqueueid = '<queueid>'
ORDER BY modifiedon DESC

-- The bot's components
SELECT name, schemaname, componenttype, botcomponentid
FROM botcomponent WHERE parentbotid = '<botid>'

-- Chained sessions (proves voice handoff)
SELECT msdyn_ocsessionid, msdyn_sessioncreationreason, msdyn_agentassignedon,
       msdyn_agentacceptedon, createdon
FROM msdyn_ocsessions
WHERE _msdyn_liveworkitemid_value = '<lwi-guid>'
ORDER BY createdon ASC
-- A successful voice escalation produces a second row with
-- msdyn_sessioncreationreason = 192350024 (Consult/Transfer)
```

---

## 7. Iteration loop — canonical

This is the default end-to-end loop the agent should perform autonomously when the user
says e.g. *"fix X on the voice agent"*. No portal clicks required.

| # | Step | Tool / command | Notes |
|---|---|---|---|
| 1 | **Locate** the right `botcomponent` | Dataverse MCP `read_query` — filter by `_parentbotid_value` and `schemaname` suffix (`.gpt.default`, `.topic.<Name>`) | Returns the YAML in `data` |
| 2 | **Edit** the YAML | Modify in memory (preserve indentation, do not reformat) | See section 5 for patterns |
| 3 | **Save** the draft | Dataverse MCP `update_record` on the `botcomponent` row, set `data` | Draft only — not live yet |
| 4 | **Publish** | `pac copilot publish --bot <your-copilot-id>` | First time: confirm with the user. Routinely thereafter. |
| 5 | **Poll status** | `pac copilot status --bot-id <your-copilot-id>` | Wait until `Published` / not `InProgress`. Note: `publish` uses `--bot`, `status` uses `--bot-id`. |
| 6 | **Verify** | Run the forensic query in section 3 after a test call | For voice: confirm chained `msdyn_ocsession` with `sessioncreationreason=192350024`, `activeagentid` ≠ bot user, transcript `outcome=HandOff` |
| 7 | **If still broken** | Run the three-way decomposition in section 2 before editing again | Don't keep tweaking blindly |

Never skip step 4 — most "my changes don't work" reports are unpublished drafts.

### Quick reference — finding your agent
- **Schema name**: query `bot` table by `name`
- **Copilot ID**: same query, capture the `botid` GUID
- **Environment**: confirm with `pac auth list` — the active profile must point at the env where the bot lives
- **Auth**: `pac auth create --url https://<your-org>.crm.dynamics.com` if needed

---

## 8. Latency floor (verified May 2026)

Realtime voice escalation has an irreducible latency that is mostly NOT the bot's fault:

- GPT decision (caller end-of-speech → escalate plan emitted): ~480 ms
- Topic dispatch + TTS "Please wait": ~75 ms
- HandOff → human session created: ~2 s
- Queue assignment: ~6 s
- Agent click-to-answer: ~6 s
- **Total ~14–20 s**, of which the bot is only ~0.5 s

Don't chase further bot-side wins — the work to do is in routing, capacity and human-side UX.

---

## 9. Anti-patterns to avoid

- Telling the GPT to "stay silent" — it can't. Tell it to invoke a topic.
- Putting handoff messages in both the GPT and the Escalate topic — the topic's
  `SendActivity` plays, so the GPT's preamble is just latency for the caller.
- Hardcoding contact GUIDs in production prompts — fine for demos, never in real systems.
- Editing live published topics in the portal during a demo — always export YAML first.
- Assuming "in queue" = "agent will see a toast" — capacity & presence still apply.
- Forgetting that option-set values in Dataverse MCP `create_record` must be **bare
  integers**, not `{"Value": n}` objects (`Newtonsoft.Json.Linq.JObject` cast error).
- Trusting `msdyn_transfercount` for voice escalations — it stays at 0 even on success.
  Use chained `msdyn_ocsession` rows instead.
