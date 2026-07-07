---
name: power-platform-ccaas-outbound-voice-agent
description: >
  Use when the user wants an "AI voice agent to call leads", "outbound qualification
  calls", "Copilot Studio voice agent over a phone number", "proactive voice", or to
  qualify marketing leads by phone and route them. Covers the CCaaS proactive-voice
  outbound pattern + Copilot Studio agent (built via pac CLI) + trigger-based Dataverse
  orchestration and write-back.
version: 1.2.0
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
qualified leads — no inside-sales team. Proven on a live SE build. Requires the
**Contact Center SKU / Customer Service Premium** (for the Proactive Engagement API).

## Architecture (the loop)
```
Lead created → Flow A (segment + consent gate) → stage "In AI Qualification"
  → Launcher flow → CCaaS_CreateProactiveVoiceDelivery → agent calls over ACS
  → agent's Capture/Complete Agent-flows write to Dataverse
  → Flow B (score & route) → sales team
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
- `pac copilot create --schemaName <x> --templateFileName t.yaml --displayName "…" --solution <s>`.
- `pac copilot clone --bot <GUID> --output-dir workspace` (clone/publish need the **GUID**).
- Edit `agent.mcs.yml` (`GptComponentMetadata.instructions:` = persona + questions +
  scoring + "call the Capture/Complete flows"), and `topics/ConversationStart.mcs.yml`
  (outbound opener). `pac copilot push` → `pac copilot publish -id <GUID>`.

### 2. Agent action flows (Agent flows designer, NOT raw API)
- **Capture** = trigger "When an agent calls the flow" (inputs leadGUID/question/answer/
  signalType) → **Add a new row** into the responses table (lookup bind `leads(leadGUID)`,
  choice values as codes) → **Respond to Copilot**.
- **Complete** = inputs leadGUID/score → **Update a row** on lead (score + a "needs review"
  stage that fires the routing flow) → **Respond to Copilot**.
- Attach both to the agent; set `leadGUID` input = **Custom value `Global.LeadId`** (never
  "Dynamically fill with AI" — it will hallucinate a GUID).

### 3. Pass the lead id in (external variable)
- Mark the agent's `LeadId` global variable **"can be set outside the agent"**.
- The launcher passes it via `InputAttributes` (see step 4); add a blank-fallback default
  in ConversationStart for Test-pane use.

### 4. Outbound launcher flow (Power Automate)
- Trigger: lead reaches the "In AI Qualification" stage.
- **Perform an unbound action** → **`CCaaS_CreateProactiveVoiceDelivery`** with:
  `ApiVersion:"1.0"`, `RequestId:<guid()>`, `DestinationPhoneNumber:<lead phone>`,
  `ProactiveEngagementConfigId:<config guid>`, `InputAttributes:'{"LeadId":"…","leadEntity":
  "lead","leadName":"…"}'`. Then stamp status/tracking columns on the lead.

### 5. Proactive Engagement config (portal — the one manual bit)
- Contact Center admin centre → **Proactive engagement** → new config: **type Copilot**,
  the agent, the **ACS number**. Its GUID is the `ProactiveEngagementConfigId` above.

## Common Mistakes & Warnings
- **No Proactive Engagement config bound to YOUR agent** → the call uses the wrong agent.
  Each agent needs its own config (don't reuse another agent's config id).
- `leadGUID` set to AI-fill → hallucinated GUID; use the external `Global.LeadId` variable.
- Building the Capture/Complete flows via raw API fails — use the **Agent flows designer**.
- See `power-platform/flows-via-web-api` for the launcher/orchestration flow gotchas
  (message codes, operationMetadataId, portal OFF/ON re-registration, team security role).

## Key Takeaway

> The engine is `CCaaS_CreateProactiveVoiceDelivery` (Contact Center SKU) driven by a
> Power Automate launcher; the agent is built as-code via `pac copilot`; the lead id flows
> in as an **external** variable via `InputAttributes`; write-back + routing are ordinary
> Dataverse-triggered flows.

---

## Lessons learned (extended)

### `pac copilot` as-code gotchas
- **`pac copilot create` from an extract-template STRIPS the voice/telephony config** and
  can set the wrong auth mode → the new bot **fails to publish with a bare "Failed" and
  `publishedon` stays null**. Fix in `settings.mcs.yml`: restore `configuration.channels`
  (Telephony/Omnichannel/MsTeams), `settings.TelephonyInitialized: true`,
  `isTelephonyEnabled: true`, `voiceProcessingMode`, and set `authenticationMode: None`
  (NOT `Integrated`, which = Custom Azure AD and needs an app reg). Copy the block verbatim
  from a working voice agent's `settings.mcs.yml`, then push + publish.
- **Cloned action files come back truncated** (missing the `action:` block with `flowId`) and
  **break publish** → delete unused ones. To (re)link a flow as a tool, use a clean
  `TaskDialog` with `action.kind: InvokeFlowTaskAction` + `flowId` + `connectionProperties(mode: Maker)`.
- **`pac copilot publish` CLI is unreliable** (crashes with `System.ArgumentException`, or a
  bare stale "Failed [hh:mm]"). When it fails with no detail, **publish from the portal** to
  see the real validation error. `publish` needs the bot **GUID** (`--bot <guid>`).
- **`pac copilot pull` before `push`** if the portal was edited, to avoid clobbering.

### Deterministic (scripted) variant — faster + no hijack
- For a predictable/compliant call, build a **deterministic** agent: `GenerativeActionsEnabled: false`
  and put the whole flow in **`ConversationStart`** — consent `Question` (Boolean) → five
  `Question` nodes (`StringPrebuiltEntity`) → one `InvokeFlowAction` → close → `EndConversation`.
- **`InvokeFlowAction` is the valid topic node to call a flow**: `kind: InvokeFlowAction`,
  `input.binding` keyed by the flow trigger **property names** (`text`, `text_1`…, `number`),
  `output.binding`, and `flowId`. Publish validates it; it needs the flow linked as a tool.
- **Batch write for speed:** collect all answers, then ONE flow call at the end that writes
  all rows + updates the lead (instead of a Capture call per answer).
- **Disable chit-chat system topics** (Greeting, Escalate, Goodbye, Thank you, Start Over) —
  they trigger on "hi"/"yes" and `CancelAllDialogs`, hijacking a scripted call.
- **Tool input fill modes matter:** unbound inputs default to *asking the caller*. Bind
  `leadGUID` = Custom `Global.LeadId`; mark question/answer/signalType/score as **AI-filled**
  (`AutomaticTaskInput` + a `description`) so they're never spoken. Pass `signalType` as a
  **label word** (Role/Need/…) and map it to the choice code **in the flow** (robust vs codes).

### Voice / TTS engine (Classic vs Realtime)
- Two engines: **Classic** (basic STT/TTS) vs **Realtime** — `settings.mcs.yml`
  `voiceProcessingMode.kind` = `ClassicVoiceProcessingMode` | `GenerativeVoiceProcessingMode`.
- **Classic:** the voice comes from the **CCaaS workstream Voice profile** (admin centre →
  workstream → Behaviors → Language → Voice). Azure neural + "turbo multilingual" voices
  (e.g. Ava, Alloy Turbo Multilingual) work here. `voiceFont: {}` on the agent = unset.
- **Realtime:** voice is set **in Copilot Studio** (Settings → Voice: Alloy/Ash/Coral…); the
  workstream Voice profile then affects **only automated messages**, not the agent. Realtime
  also changes turn-taking/barge-in and is region/licensing-dependent.
- Pitfall: switching to Realtime makes a workstream-set voice "stop applying" — because voice
  control moves to Copilot Studio. If the workstream voice is what you configured, stay Classic.

### Caller-ID / outbound number
- Outbound presents the **number bound to the workstream** (Behaviors → Phone number).
  An inherited config can dial a wrong-country number (which carriers may relabel with an
  odd CLI). Fix = assign the correct-country **ACS number** to the outbound workstream
  (provision it first if needed).

### Recording, transcript & linking the conversation to the lead
- Each call creates a **conversation** (`msdyn_ocliveworkitem`) + a **transcript**
  (`msdyn_transcript`, stored as a text note `Messages_file.txt`). **Audio recording is a
  separate toggle** (workstream → Recording and transcription → Record calls) and is OFF by
  default — and needs a consent notice (regional/telecom review).
- **Conversations bind their customer to contact/account, NOT lead** (`msdyn_customer`
  targets = account/contact; `msdyn_issueid` = incident only). An inherited proactive config
  files every conversation under a **placeholder customer + case** — so transcripts/recordings
  land on that case, not your lead.
- `msdyn_ocliveworkitem.regardingobjectid` **does accept `lead`** (polymorphic), so a
  conversation *can* be related to a lead (shows on the lead timeline). The blocker is
  correlation: **basic voice agents expose no conversation-id variable** (`System.Conversation.Id`
  is invalid on Classic — it fails publish); a **"Conversation ID" context variable exists
  only on REALTIME voice agents**. So: use realtime to capture the id and stamp
  `regardingobjectid = lead`, or a time-proximity linker on basic voice.
- **Lead-timeline equivalent that always works:** in the write-back flow, create a **completed
  Phone Call activity regarding the lead** (`regardingobjectid_lead_phonecall@odata.bind =
  leads(<id>)`, `directioncode: true`, close `statecode 1 / statuscode 2`) containing the
  Q&A + score + AI rationale. That gives sellers the conversation history on the lead.

### AI scoring instead of Power Fx
- Replace a Power Fx keyword-scoring node with an **AI Builder prompt** run inside the batch
  flow — reasons over the answers (synonyms/sentiment/context) and returns strict JSON
  `{score, band, rationale}`. See `power-platform/ai-builder-prompt-in-flow`.
