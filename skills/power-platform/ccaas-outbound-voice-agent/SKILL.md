---
name: power-platform-ccaas-outbound-voice-agent
description: >
  Use when the user wants an "AI voice agent to call leads", "outbound qualification
  calls", "Copilot Studio voice agent over a phone number", "proactive voice", or to
  qualify marketing leads by phone and route them. Covers the CCaaS proactive-voice
  outbound pattern + Copilot Studio agent (built via pac CLI) + trigger-based Dataverse
  orchestration and write-back.
version: 1.5.0
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
qualified leads — no inside-sales team. Proven on the Core42 MQL build. Requires the
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

## Lessons learned (extended — Core42 build)

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
  (e.g. Ava, **Alloy Turbo Multilingual**) work here. `voiceFont: {}` on the agent = unset.
- **Realtime:** voice is set **in Copilot Studio** (Settings → Voice: Alloy/Ash/Coral…); the
  workstream Voice profile then affects **only automated messages**, not the agent. Realtime
  also changes turn-taking/barge-in and is region/licensing-dependent.
- Pitfall: switching to Realtime made a workstream-set Alloy "stop applying" — because voice
  control moved to Copilot Studio. If the workstream voice is what you configured, stay Classic.

### Caller-ID / outbound number
- Outbound presents the **number bound to the workstream** (Behaviors → Phone number).
  An inherited config can dial a wrong-country number (e.g. a UK number for UAE calls),
  which carriers may relabel with an odd CLI. Fix = assign the correct-country **ACS number**
  to the outbound workstream (provision it first if needed).

### Recording, transcript & linking the conversation to the lead
- Each call creates a **conversation** (`msdyn_ocliveworkitem`) + a **transcript**
  (`msdyn_transcript`, stored as a text note `Messages_file.txt`). **Audio recording is a
  separate toggle** (workstream → Recording and transcription → Record calls) and is OFF by
  default — and needs a consent notice (UAE/regional).
- **Conversations bind their customer to contact/account, NOT lead** (`msdyn_customer`
  targets = account/contact; `msdyn_issueid` = incident only). An inherited proactive config
  files every conversation under a **placeholder customer + case** — so transcripts/recordings
  land on that case, not your lead.
- `msdyn_ocliveworkitem.regardingobjectid` **does accept `lead`** (145 targets), so a
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

---

## Lessons learned (extended — logistics build): why the "Complete" step keeps failing

The completion call (agent → flow at end of the questionnaire) is the single most fragile
part of a voice agent. On one logistics build it "crashed to how-can-I-help after the last question"
for hours. Root causes, in the order they bite — **all must be right**:

1. **Don't call the completion flow through a TOOL wrapper — call it DIRECTLY.** A
   `BeginDialog` → `TaskDialog` tool for the final write repeatedly **corrupts** (loses its
   flow binding; portal shows a blank *Type* column / "something went wrong" / 0 inputs).
   Instead put a **direct `InvokeFlowAction`** node in the topic (like the Start flow, which
   never corrupts). Delete the tool file; the flow is referenced by `flowId` only. Bonus: a
   flow referenced only by `flowId` (not in the pac `workflows/` folder) is **not stripped**
   by `pac copilot push`.
2. **Answers must be `Global.*`, never `Topic.*`.** A flow/tool invoked from a topic runs in
   its **own** Topic scope, so `Topic.Ocean` etc. are blank inside its input bindings. Store
   every captured answer in `Global.*` and bind the flow inputs to `Global.*`.
3. **Make ALL Skills-trigger inputs string-typed; convert inside the flow.** Typed `number`/
   `boolean` trigger inputs cause the Copilot Skills invocation to be **rejected before the
   flow runs** (nothing is written). Set every trigger property `type: string`, bind from the
   topic as text (`Text(Coalesce(Global.Ocean,0))`, `If(Global.Consent,"true","false")`), and
   convert in-flow (`int()`/`float()`/`equals(toLower(x),'true')`).
4. **Do NOT mark inputs `required`.** A blank answer must not reject the whole invocation.
5. **ROOT CAUSE that hid for hours — field length.** A short string summary column
   (e.g. `mse_buyingstage` MaxLength 30) rejects the **ENTIRE Update** when a natural voice
   answer overflows it: `OpenApiOperationParameterValidationFailed … maximum length '30' but
   is of length '34'`. Fix: **widen** the free-text fields (e.g. to 850) AND **truncate**
   text in the flow (`substring(v,0,min(850,length(v)))`) as a safety net. Voice answers are
   long and chatty — size text fields for prose, not codes.
6. **Respond FAST, then do heavy work async.** Put `Respond to Copilot` right after the quick
   `Update`, and run the answer-persistence `Foreach` **after** Respond — so the loop can't
   time out the ~2s voice turn. (Even if it did, Dataverse commits continue server-side.)
7. **pac strips `Foreach`-containing flows on push.** `pac copilot push` silently keeps the
   OLD version of a flow whose clientdata has a batch `Foreach`. Re-apply that flow's
   clientdata via **API PATCH** after every push (or keep the flow out of the pac project).

### The diagnostic technique that cracked it (use when the portal hides the error)
- The CLI/portal often shows only a bare "Failed"/"an error occurred". To get the REAL error:
  1. Add an **unconditional first action** to the flow that creates a task whose subject/
     description = the raw trigger inputs (`@concat('qid=[', coalesce(triggerBody()?['text'],
     'NULL'),'] ...')`). Proves the flow fired and shows exactly what it received.
  2. Wrap the failing action in a **Scope**, add a catch action `runAfter` the scope with
     `[Failed,Skipped,TimedOut]` that writes `@{string(result('Scope_x'))}` (the full error)
     to a task description. One call then reveals the precise `OpenApi…ValidationFailed`.
  Remove both after diagnosis.

### Related config-driven orchestration patterns (proven same build)
- **Dynamic questionnaire by lead type:** the Start flow reads `lead.mse_leadtype` (int
  choice), resolves an active questionnaire mapped via an **integer** `mse_leadtypevalue`
  (don't compare to a free-text field), else the single active default, else fail safely; it
  stamps the questionnaire + a version on the qualification and returns the id. Remove any
  hard-coded questionnaire GUID from the agent tools.
- **Lifecycle gating (score-once / route-once):** add a status field (In Progress/Completed/
  Scored/Routed/…) + `completedon/scoredon/routedon`. Score triggers on the **Completed**
  transition and runs only when `scoredon` empty; Route triggers on **Scored**, checks for an
  existing task by a stored `qualificationref`+purpose (idempotent), then stamps `routedon`.
  Respect the configured operator per qualifying question (reject unsupported, don't silently
  treat all as `>=`).

---

## Lessons learned (extended — logistics "RT" build): GENERATIVE ORCHESTRATION for voice

The opposite of the scripted variant: **let the LLM ask the questions** from the agent
instructions and **call a completion tool itself** (generative orchestration ON,
`GenerativeAIRecognizer`). Feels far more natural on voice (handles out-of-order answers,
"I ship both", digressions, number read-back). This is usually the **better** design than a
scripted `ConversationStart` — do NOT downgrade a working generative agent to scripted nodes.

### Where the pieces live + how to edit them safely
- **`pac` (2.8.1) does NOT round-trip generative components.** `pac copilot pull/push` leaves
  `agent.mcs.yml` empty and never writes flow-tools to `actions/`. So a `pac copilot push`
  after designer work **wipes instructions/tools**. RULE: after any designer edit to
  instructions/tools, do **NOT push** — edit the specific component's **`data`** column via
  Web API PATCH, then `pac copilot publish --bot <id>` (server-side publish, ignores local).
- Everything is stored in `botcomponents.data` (NOT `content`, a File col that 204s):
  - **Instructions** = the **type-15** component (name = agent display name),
    `data = kind: GptComponentMetadata` + `instructions: |-` block scalar (+ `gptCapabilities`,
    `aISettings.model.modelNameHint`).
  - **Flow exposed as a tool** = a **type-9** component, `data = kind: TaskDialog` with
    `modelDisplayName`/`modelDescription`, `inputs` (ManualTaskInput bound to `=Global.x` or a
    constant; **AutomaticTaskInput** = orchestration slot-fills), `action.InvokeFlowTaskAction`
    + `flowId`.
  - **Topic** = type-9 `data` = the AdaptiveDialog YAML (same as the .mcs.yml body **without**
    the `mcs.metadata` header).
- You **can create tools/variables via API** (`POST /botcomponents`, componenttype 9 / 12,
  `parentbotid@odata.bind`) and they publish fine. Global var data = `kind: Variable\nname: x\n
  scope: Conversation\n...`.
- **Line endings differ per component** — tool `data` came back **CRLF**, topic `data` **LF**.
  Match the target's existing endings when string-editing or `.replace()` silently misses.

### The completion tool — the #1 gotcha (again, differently)
- **A bare tool with no `inputs:` block never binds the record id.** The LLM can't supply the
  `qualificationId` GUID (it's in `Global.qualificationId`, not something the caller says), so
  the flow completes nothing. **Always add `inputs:` with `ManualTaskInput text = Global.qualificationId`**
  (+ `text_1 = "Connected"` for a constant CallResult). Leave the data fields as
  `AutomaticTaskInput` and give each a **`description:`** (survives publish, improves phrasing).
- **Publish blocker `BindingKeyNotFoundError`**: an `InvokeFlowAction`/tool binding a flow input
  the flow doesn't have (e.g. binding `text_2` when the Start flow only has `text`+`text_1`)
  **fails publish**. The **designer** surfaces the exact component + `bindingKey`; `pac`/CLI
  only says a bare "Failed" and leaves `publishedon` unchanged. Remove the stale binding.

### Dynamic question-set (BDL fast-track) in a generative agent — adherence, not substitution
- Variable references in instructions **do** work: `{Global.segment}` substitutes (confirmed —
  other agents use `{Global.EntityNameList}` etc.), and a global set in **ConversationStart** is
  available to the Q&A turns. Plumbing: capture the resolved questionnaire from the Start flow
  output (`output.binding.questionnaireId: Global.questionnaireId`) then
  `SetVariable Global.segment = If(Global.questionnaireId = "<bdl-guid>", "BDL Fast-Track", "Standard")`.
- **The model will IGNORE a scoping note that conflicts with a strong prescriptive list.** An
  emphatic "ask these 11, do not skip" overrides an appended "if BDL ask 3". Fix: make the
  branch **DOMINANT, FORBIDDING, and at the TOP** of the instructions — e.g. "This call's
  segment is {Global.segment}. If BDL Fast-Track: ask ONLY these THREE… you are FORBIDDEN from
  asking… IGNORE the numbered list below." Then it obeys.
- **Debug the runtime value cheaply:** add a **test-mode-only** `SendActivity`
  (`ConditionGroup condition: =System.Conversation.InTestMode = true`) printing
  `segment='{Global.segment}' questionnaireId='{Global.questionnaireId}'`. One run tells you if
  the value is right (isolates "variable wrong" vs "model not obeying"). Remove it after.
- **Scoping the QUESTIONS is not enough — the completion TOOL re-collects the rest.** After the
  3 fast-track questions, a completion tool with 9 `AutomaticTaskInput`s makes orchestration go
  collect the other 6 (tell-tale: robotic "X has been updated to Y" phrasing, unlike the
  agent's natural questions). Fix: give the fast-track its **own tool with ONLY the 3 inputs**
  and route to it **by name** in the instructions ("call the tool named 'Complete Qualification
  BDL', not the standard one"). The tool's input list — not just the questions — governs what
  gets asked at the end.

### Knowledge, escalation, publish quirks
- **File knowledge must be added in the designer's Knowledge tab** (it uploads + **indexes**).
  Do NOT create the **type-14** FileAttachment component via API: an unindexed / null-`filedata`
  knowledge file **crashes `pac copilot pull`** with `404 No file attachment found for
  attribute: filedata`. (If a clone left one broken, repair by copying `filedata/$value` from a
  good bot: `GET .../botcomponents(src)/filedata/$value` → `PATCH .../botcomponents(dst)/filedata`
  with `Content-Type: application/octet-stream` + `x-ms-file-name`.)
- **Escalation vs instructions:** "NEVER escalate / never trigger the Escalate topic" in the
  instructions fights the **Escalate** system topic (which triggers on "escalate"/"speak to a
  human"). To let the agent escalate, remove that line; to fully block it, also disable the
  topic trigger.
- **`pac copilot publish` prints "Failed" ambiguously** — confirm via `bots(id).publishedon`
  (updated = real success). A genuine failure leaves it unchanged and hides the reason;
  **publish in the designer** to get the exact validation error.

### Key takeaway (generative variant)
> Prefer generative orchestration for natural voice: instructions ask the questions, the agent
> calls a completion **tool** that **binds `qualificationId`**. Edit instructions/tools via the
> `botcomponents.data` column + server-side publish (pac can't round-trip them). Vary the
> question set with a top-of-instructions FORBIDDING conditional on a `{Global.segment}` var
> **and** a matching **reduced-input tool** — the tool's inputs, not just the questions, decide
> what's asked. Knowledge = designer-only.

---

## Lessons learned (extended — logistics DETERMINISTIC 3-topic build + live transfer)

Validated end-to-end on real calls: greeting+consent → redirect to **Qualify BDL** (3 Qs) or
**Qualify Standard** (10 Qs) → Complete flow (AI parse) → Completed→Scored→Routed→MQL, plus a
**hot-lead live transfer** to Contact Center. Key gotchas beyond the generative build:

### Authoring topics via API so the DESIGNER still renders them
- **Topic `botcomponents.data` MUST be designer-canonical or the canvas shows an EMPTY topic**
  (only the trigger node), and a subsequent designer save writes back the empty version,
  silently wiping your work. PyYAML `dump` output (LF + non-indented block sequences) triggers
  this even though it runs fine at runtime. Fix: emit with **`ruamel.yaml`**:
  `y=YAML(); y.indent(mapping=2, sequence=4, offset=2); y.width=100000; y.preserve_quotes=True`,
  then force **CRLF** (`.replace("\r\n","\n").replace("\n","\r\n")`). Matches v2's shipped format.
- **Split into topics via redirects:** `- kind: BeginDialog` + `dialog: <botschema>.topic.<Name>`.
  Redirect-**target** custom topics use `beginDialog.kind: OnRecognizedIntent` with
  `includeInOnSelectIntent: false` + an obscure trigger phrase (NOT `OnRedirect` — that's for CS
  system topics and fails publish). Put completion at the END of each track topic; all answers in
  `Global.*` so no cross-topic parameter wiring is needed.
- **Free text beats typed entities:** `NumberPrebuiltEntity` LOOPS when the caller says "no". Use
  `StringPrebuiltEntity` for every answer and parse to numbers downstream (AI Builder).

### Deterministic config + flow linking
- **`GenerativeActionsEnabled: false`** (bot `configuration.settings`) makes `InvokeFlowAction`
  require flows to be **explicitly linked**; if a designer edit pruned the link you get
  `InvalidReferenceError CloudFlow NotFound`. Simplest: keep `true` (matches v2, flows resolve),
  the scripted topics still run deterministically. If a designer edit unlinks a flow, **re-select
  it in the action node in the designer** to restore the connection.
- **Remove auto-added flow output bindings you don't use:** re-linking a flow in the designer can
  bind ALL outputs (e.g. `questionnaireVersion`) → `FlowActionBadRequest` on a type mismatch.
  Keep only the outputs you consume.

### THE flow-output → topic-variable TYPE-BINDING TRAP (cost hours)
- Adding a **NEW** flow `Respond` output and binding it in a topic via API fails at RUNTIME:
  `FlowActionBadRequest … evaluated to type 'Number/StringDataType', expected 'UnspecifiedDataType'`.
  Cause: the agent's `InvokeFlowAction` caches the flow's output signature; a newly-added output
  isn't in it, so the bound Global var stays **unspecified** and rejects any typed value. Global
  var components carry **no declared type** (type is inferred from the binding), so you can't fix
  it by "typing the var". Number AND string both fail.
- **FIX: don't add a new output — REUSE an existing working one.** We changed the flow's existing
  `status` output from `'Completed'` to `@if(greater(int(coalesce(json(outputs('Compose_ParsedNumbers'))?['ocean'],0)),100),'CompletedHot','Completed')`
  and branched the topic on `=Global.completeStatus = "CompletedHot"`. (If a genuinely new output
  is unavoidable, **map it in the DESIGNER** so the agent refreshes its cached flow signature.)

### Hot-lead live transfer (Journey 1) pattern
- Reuse the **Escalate** system topic's action: `- kind: TransferConversationV2` with
  `transferType: { kind: TransferToAgent, context: { kind: AutomaticTransferContext } }`. Its own
  trigger is a disabled `zzz…` dummy phrase — inline the action into your track topic instead.
- Topic tail: `complete_qualification (status→Global.completeStatus)` → `SetVariable
  Global.WantsTransfer=false` → `ConditionGroup (=Global.completeStatus="CompletedHot"){ Boolean
  Question → Global.WantsTransfer }` → `ConditionGroup (=Global.WantsTransfer=true){ SendActivity
  + TransferConversationV2 } else { close + EndConversation }`. Needs an Omnichannel agent signed
  in to receive.

### `float()` on free-text answers
- The batch answer loop did `float(triggerBody()?['number'])` on the RAW answer ("150 TEUs" → throws
  `float invalid parameter`). It runs AFTER `Respond` so the agent got success but the **flow run
  FAILED** and answer rows weren't written. Repoint to the AI-parsed value:
  `float(coalesce(json(outputs('Compose_ParsedNumbers'))?['ocean'],0))`.

### FLOW clientdata PATCH does NOT recompile to runtime
- Editing `workflows(id).clientdata` via API updates the definition but the **running flow keeps
  the old compiled version**. After ANY API flow edit the user must open it in the designer and
  **Save** (recompiles clientdata→runtime). Symptom: your verified `clientdata` change is present
  but the next call still hits the old behaviour. (Topic `botcomponents.data` PATCH + `pac copilot
  publish` IS live; only cloud-flow clientdata has this staleness.)

### Fast debugging tools (stop using a phone call as your debugger)
Real-call round-trips (publish → propagate → dial → **3–4 min transcript lag** → diagnose) were the
biggest time sink. These `tools/` scripts collapse it to one command (Dataverse `flowruns` +
`conversationtranscripts`, `~/scripts/auth.py`):
- **`flow-diag.py [flow]`** — instant PASS/FAIL + timing of the last flow run(s) from the
  `flowruns` table (no transcript wait); on failure pulls the agent-side `ErrorTraceData`. `--watch`
  live-tails the next run.
- **`call-check.py [lead]`** — one-shot post-call view: parsed numbers + Completed/Scored/Routed,
  the flow run status, and the transcript turns + any error. `--watch` polls for the next call.
- **`preflight.py [bot]`** — pre-publish validator: canonical-YAML, `NumberPrebuiltEntity`,
  `InvokeFlowAction` output bindings vs the flow's `Respond` schema (catches the NUMBER-output
  trap), `float(triggerBody/items…)`, and `=Global.*` tool-scope bindings.
- **Transcripts lag ~3–4 min**; `flowruns` is near-real-time — check `flow-diag` first for a fast
  pass/fail, then `call-check` once the transcript flushes for the spoken turns + exact error.

### Key takeaway (deterministic variant)
> Author topics with **ruamel canonical YAML (CRLF + indented sequences)** or the canvas silently
> shows an empty topic. Never bind a **new** flow output in a topic (unspecified-type trap) —
> **reuse an existing output** (`status` → a signal word). After any **flow clientdata** API edit,
> the user must **Save the flow in the designer** to make it live. Debug with `flowruns`
> (`tools/flow-diag.py`), not a 3-4 minute transcript wait.
