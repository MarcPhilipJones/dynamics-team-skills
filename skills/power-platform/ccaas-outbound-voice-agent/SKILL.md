---
name: power-platform-ccaas-outbound-voice-agent
description: >
  Use when the user wants an "AI voice agent to call leads", "outbound qualification
  calls", "Copilot Studio voice agent over a phone number", "proactive voice", or to
  qualify marketing leads by phone and route them. Covers the CCaaS proactive-voice
  outbound pattern + Copilot Studio agent (built via pac CLI) + trigger-based Dataverse
  orchestration and write-back.
version: 1.0.0
author: Jamie Barker
tags:
  - power-platform
  - copilot-studio
  - voice-agent
  - contact-center
  - proactive-engagement
  - outbound
---

# Outbound AI voice qualification (CCaaS proactive voice + Copilot Studio)

> **Trigger**: "AI agent that calls leads to qualify them" / "outbound proactive voice"

Pattern for an AI voice agent that places **outbound** calls (over an existing ACS
number), runs a qualification script, writes answers to Dataverse, scores, and routes
qualified leads — no inside-sales team. Requires the **Contact Center SKU / Customer
Service Premium** (for the Proactive Engagement API).

## Architecture (the loop)
```
Lead created -> Flow A (segment + consent gate) -> stage "In AI Qualification"
  -> Launcher flow -> CCaaS_CreateProactiveVoiceDelivery -> agent calls over ACS
  -> agent's Capture/Complete Agent-flows write to Dataverse
  -> Flow B (score & route) -> sales team
```

## Prerequisites
- Contact Center SKU / CS Premium; an ACS number already provisioned.
- Dataverse schema for capture (a child "responses" table + lead score/stage columns).

## Step-by-Step Procedure

### 1. Build the Copilot Studio agent via pac CLI (build-from-scratch)
- `pac copilot extract-template --bot <existing-voice-agent> --templateFileName t.yaml`
  (seed from a WORKING voice agent so the realtime-voice config transfers).
- **Fix the template:** set `entity.authenticationMode: Integrated` when
  `accessControlPolicy: GroupMembership` — else `create` rolls back.
- `pac copilot create --schemaName <x> --templateFileName t.yaml --displayName "..." --solution <s>`.
- `pac copilot clone --bot <GUID> --output-dir workspace` (clone/publish need the **GUID**).
- Edit `agent.mcs.yml` (`GptComponentMetadata.instructions:` = persona + questions +
  scoring + "call the Capture/Complete flows"), and `topics/ConversationStart.mcs.yml`
  (outbound opener). `pac copilot push` -> `pac copilot publish -id <GUID>`.

### 2. Agent action flows (Agent flows designer, NOT raw API)
- **Capture** = trigger "When an agent calls the flow" (inputs leadGUID/question/answer/
  signalType) -> **Add a new row** into the responses table (lookup bind
  `<entityset>(leadGUID)`, choice values as codes) -> **Respond to Copilot**.
- **Complete** = inputs leadGUID/score -> **Update a row** on lead (score + a "needs review"
  stage that fires the routing flow) -> **Respond to Copilot**.
- Attach both to the agent; set `leadGUID` input = **Custom value `Global.LeadId`** (never
  "Dynamically fill with AI" — it will hallucinate a GUID).

### 3. Pass the lead id in (external variable)
- Mark the agent's `LeadId` global variable **"can be set outside the agent"**.
- The launcher passes it via `InputAttributes` (see step 4); add a blank-fallback default
  in ConversationStart for Test-pane use.

### 4. Outbound launcher flow (Power Automate)
- Trigger: lead reaches the "In AI Qualification" stage.
- **Perform an unbound action** -> **`CCaaS_CreateProactiveVoiceDelivery`** with:
  `ApiVersion:"1.0"`, `RequestId:<guid()>`, `DestinationPhoneNumber:<lead phone>`,
  `ProactiveEngagementConfigId:<config guid>`, `InputAttributes:'{"LeadId":"...","leadEntity":
  "lead","leadName":"..."}'`. Then stamp status/tracking columns on the lead.

### 5. Proactive Engagement config (portal — the one manual bit)
- Contact Center admin centre -> **Proactive engagement** -> new config: **type Copilot**,
  the agent, the **ACS number**. Its GUID is the `ProactiveEngagementConfigId` above.

## Common Mistakes & Warnings
- **No Proactive Engagement config bound to YOUR agent** -> the call uses the wrong agent.
  Each agent needs its own config (don't reuse another agent's config id).
- `leadGUID` set to AI-fill -> hallucinated GUID; use the external `Global.LeadId` variable.
- Building the Capture/Complete flows via raw API fails — use the **Agent flows designer**.
- See `power-platform/flows-via-web-api` for the launcher/orchestration flow gotchas
  (message codes, operationMetadataId, portal OFF/ON re-registration, team security role).

## Key Takeaway

> The engine is `CCaaS_CreateProactiveVoiceDelivery` (Contact Center SKU) driven by a
> Power Automate launcher; the agent is built as-code via `pac copilot`; the lead id flows
> in as an **external** variable via `InputAttributes`; write-back + routing are ordinary
> Dataverse-triggered flows.
