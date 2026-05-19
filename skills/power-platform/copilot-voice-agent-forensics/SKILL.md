---
name: copilot-voice-agent-forensics
description: >
  Complete end-to-end runbook for Microsoft Copilot Studio Realtime Voice
  agents integrated with Dynamics 365 Contact Center. Covers headless authoring
  (pull/edit/PATCH/publish GPT instructions and topic YAML from Dataverse),
  runtime forensics (oclive workitem, sessions, queue routing), conversation
  transcript forensics (activity stream parsing, latency reconstruction, tool
  dispatch timing), and the iterative seven-step tuning loop. Use when an
  engineer needs to debug silence, wrong topic, no transfer, duplicate case,
  wrong title, or any other voice-agent regression.
version: 1.0.0
author: Marc
tags:
  - copilot-studio
  - voice-agent
  - realtime
  - dynamics-365-contact-center
  - forensics
  - transcript-analysis
  - debugging
  - runbook
---

# Copilot Voice Agent — Forensics & Iterative Tuning

> **Status**: Production runbook · **Last updated**: 2026-05-18
> **Audience**: Power Platform / D365 makers, support engineers, AI ops engineers.
> **Companion skill**: [`copilot-studio-voice-agent`](../copilot-studio-voice-agent/SKILL.md) — the original escalation-focused runbook. This skill is the **broader, end-to-end** version covering authoring, runtime forensics, and conversation forensics.

---

## 1. What this skill is, and what it can do

This skill is a **complete, hands-on runbook** for working with **Microsoft Copilot Studio Realtime Voice agents** (the speech-to-speech, GPT-orchestrated agents that plug into Dynamics 365 Contact Center). It is written so an engineer who has never touched one of these agents before can pick it up, configure their environment, and become productive within a single session — and so an engineer who already uses them can use it as a forensic toolkit to debug, tune, and iterate quickly.

It covers **four interlocking capabilities**, all of which build on the same Dataverse Web API + PAC CLI foundation:

1. **Authoring & editing the agent without using the Copilot Studio UI.** You can pull the agent's GPT instructions (the "system prompt" that drives the orchestrator) and any topic YAML straight out of Dataverse over the Web API, edit it locally in your editor of choice (VS Code is assumed throughout, but any text editor works), PATCH it back, and publish — all from a terminal. This is dramatically faster than clicking through the UI when you are doing tight iteration loops and it gives you proper version control, diffs, and the ability to script bulk changes.

2. **Forensic analysis of the agent's runtime behaviour.** When a call goes wrong — silence, wrong topic, no transfer, duplicate case, wrong title — there is a forensic trail in Dataverse. This skill shows you exactly which tables to query, what the columns mean, and how to interpret common patterns. You can answer questions like *"did the Escalate topic actually fire?"*, *"how long did the tool call take?"*, *"who is the active agent on this work item?"*, and *"why is this call sitting in the queue?"* without ever leaving your terminal.

3. **Forensic analysis of the conversation itself.** Every voice call produces a `conversationtranscript` record containing the full activity stream — every user utterance (transcribed), every bot utterance, every plan dispatch (the orchestrator deciding to call a tool or invoke a topic), every plan finish, and every event. Parsed correctly, this stream lets you reconstruct the timeline of the call to ~100ms accuracy, measure dead-air gaps, identify which tool calls fired and how long they took, and pinpoint the *exact* turn at which a behaviour regression was introduced. This is the most powerful diagnostic tool you have for tuning realtime voice — it tells you not just *that* something went wrong but *exactly when* and *what the planner was doing at that moment*.

4. **The iterative tuning loop that ties it all together.** Voice agents are inherently empirical — you cannot statically prove a prompt change works; you have to test it on real audio. This skill defines a canonical seven-step loop (pull → edit → patch → publish → test-call → wait-for-transcript → forensic-analyse) that you repeat until the behaviour is right. The loop is fast — typically two to three minutes per cycle once you have the snippets memorised — and it is the rhythm of all serious voice-agent work.

### What this skill is NOT for

- It is **not** a guide to building a Copilot Studio agent from scratch in the UI. Use Microsoft Learn for the initial setup; come here once you have a deployed agent that you want to iterate on.
- It is **not** about classic Power Virtual Agents (the non-realtime, chat-only version). The data model is similar but the orchestration model is different.
- It is **not** about Azure OpenAI direct integration or Azure AI Foundry; this is Copilot-Studio-flavoured GPT orchestration.

### Trigger phrases — invoke this skill when the user says any of:

- "analyse the last call", "forensics on the agent", "what did the bot do on that call"
- "edit the agent prompt", "update the GPT instructions", "patch the gpt.default"
- "the bot went silent", "the bot stalled", "there was a long pause"
- "the topic didn't fire", "escalation didn't work"
- "set up the voice agent tooling", "first-time setup for the voice agent"
- "pull the agent YAML", "what version of the prompt is live"
- "publish the voice agent", "republish after the edit"
- "find the transcript for the last call", "show me the conversation"

---

## 2. Glossary — terms you will encounter constantly

| Term | Meaning |
|---|---|
| **Agent / Bot / Copilot** | The same thing in three eras. Internally Dataverse still calls it `bot` (table) but the UI calls it Copilot, and people say "agent". A single record in the `bot` table. |
| **botcomponent** | The Dataverse table that holds every piece of an agent's definition — GPT instructions, topics, settings, connectors. Each row is one component. |
| **GPT instructions (`*.gpt.default`)** | The big system-prompt YAML that drives the orchestrator. One `botcomponent` row per agent. This is the file you will edit most often. |
| **Topic** | A deterministic flow (greeting, escalate, end-of-conversation, error handling). YAML with `kind: AdaptiveDialog`. Stored as `botcomponent` rows. |
| **Generative orchestrator** | The runtime that, on every user turn, decides whether to invoke a topic, call a tool, or generate speech from the GPT instructions. |
| **Realtime voice** | The speech-to-speech mode (vs. the older "voice as a chat channel" mode). Latency-sensitive. The orchestrator and the speech model share a low-latency pipeline. |
| **Tool / action / plugin / connector** | Things the orchestrator can invoke as part of a plan. Includes MCP tools (e.g. Dataverse MCP `create_record`), Power Automate flows, custom connectors, and built-in topics. |
| **Plan dispatch** | A single decision by the orchestrator to invoke one tool or topic. Logged in the transcript as `DynamicPlanReceived` → `DynamicPlanStepTriggered` → `DynamicPlanStepFinished` → `DynamicPlanFinished`. |
| **Workstream** | The D365 Contact Center construct that routes incoming calls into queues and onto agents. `msdyn_liveworkstream`. |
| **Work item** | A single live conversation as tracked by Omnichannel. `msdyn_ocliveworkitem`. Contains escalation count, active agent, queue, etc. |
| **Session** | The agent's involvement in one work item. Multiple sessions if a call is transferred. `msdyn_ocsession`. |
| **Conversation transcript** | The full activity log of one call, stored as a JSON blob in `conversationtranscript.content`. Typically lands in Dataverse 1-5 minutes after the call ends. |
| **PAC CLI** | Power Platform CLI — `pac` command. Used for auth profiles and `pac copilot publish`. |
| **MCP** | Model Context Protocol — how Copilot Studio agents (and this VS Code agent) talk to Dataverse and other services as tools. |
| **Definition / Activation pair** | When a classic XAML workflow is activated, Dataverse creates two rows — type=1 (Definition) and type=2 (Activation) linked by `parentworkflowid`. Both show `statecode=Activated`. This LOOKS like a duplicate but is not. |
| **featuremask** | A column on the `subject` table. `NULL` = subject hidden from Customer Service admin UI; `1` = visible. New subjects created via Web API default to `NULL`. |

---

## 3. Prerequisites — first-time setup for a new engineer

This section assumes you are on Windows with PowerShell 7. The skill works on macOS/Linux too — substitute `pwsh` and adjust path syntax.

### 3.1. Install tooling

Install in this order. Each step is independent — if you already have a working version, skip it.

```pwsh
# 1. PowerShell 7 (skip if already installed — check with $PSVersionTable.PSVersion)
winget install --id Microsoft.PowerShell -e

# 2. Azure CLI — used to get Dataverse bearer tokens
winget install --id Microsoft.AzureCLI -e

# 3. Power Platform CLI (PAC) — used to publish the agent and manage auth profiles
winget install --id Microsoft.PowerPlatformCLI -e
# Or via dotnet:  dotnet tool install --global Microsoft.PowerApps.CLI.Tool

# 4. Node.js (only needed if you also work on PCF controls in the same workspace)
winget install --id OpenJS.NodeJS.LTS -e

# 5. VS Code + REST Client extension (for ad-hoc Web API calls in .http files)
winget install --id Microsoft.VisualStudioCode -e
code --install-extension humao.rest-client
```

Verify everything resolves on PATH:

```pwsh
pwsh --version          # 7.x
az --version            # 2.6x or newer
pac --version           # 1.x or 2.x
node --version          # v20+ (optional)
code --version          # any recent
```

### 3.2. Authenticate to your tenant

You need **two** authentications: one for `az` (so you can mint Dataverse bearer tokens on demand) and one for `pac` (so you can publish the agent).

```pwsh
# Azure CLI — opens a browser for interactive sign-in
az login --tenant <your-tenant>.onmicrosoft.com
az account show           # confirm the right user/tenant

# PAC CLI — create a named profile so you can switch tenants cleanly
pac auth create --name MyEnvProfile --url https://<orgname>.crm<region>.dynamics.com
pac auth list             # confirm profile is "Active"
pac auth select --name MyEnvProfile     # if you have multiple profiles
```

> **Tip**: Always keep the PAC profile name and the Dataverse env URL in your project's `copilot-instructions.md` so the agent picks them up automatically. See this workspace's `.github/copilot-instructions.md` for the canonical template.

### 3.3. Identify your environment's three magic IDs

You will reference these constantly. Find them once, save them, and move on.

| ID | What it is | How to find it |
|---|---|---|
| **Dataverse env URL** | `https://<orgname>.crm<region>.dynamics.com` | Power Platform admin centre → your env → URL |
| **Copilot (bot) ID** | GUID of the agent itself in the `bot` table | Copilot Studio → Open agent → URL contains `botId=...`, or query `bots?$select=botid,name` |
| **`gpt.default` botcomponent ID** | GUID of the GPT-instructions row | Query: `botcomponents?$filter=schemaname eq '<botschema>.gpt.default'&$select=botcomponentid` (see §5 for the snippet) |

Save them at the top of a notes file or — better — into the workspace's Copilot instructions so future sessions inherit them automatically.

### 3.4. Verify you can reach Dataverse

A one-line smoke test:

```pwsh
$env_ = 'https://<orgname>.crm<region>.dynamics.com'
$tok = az account get-access-token --resource $env_ --query accessToken -o tsv
(Invoke-RestMethod -Uri "$env_/api/data/v9.2/WhoAmI" -Headers @{Authorization="Bearer $tok"}).UserId
```

If this returns a GUID, you are ready. If it returns 401, redo `az login`. If it returns 403, your user lacks Dataverse access — request a role.

### 3.5. (Optional but recommended) Configure the Dataverse MCP server

If you are using this skill from inside VS Code with GitHub Copilot agent mode, register the Dataverse MCP server. It lets the agent introspect tables and run queries natively rather than relying on hand-written cURL/PowerShell. The workspace's `.vscode/mcp.json` is the template — copy it into any new workspace and adjust the URL.

---

## 4. Quick orientation — the data model in one diagram

```
bot  (one row per agent)
 └── botcomponent  (many rows per agent — the agent's "source code")
      ├── *.gpt.default        ← THE big system prompt (this is what you'll edit most)
      ├── *.topic.Greeting     ← deterministic flow
      ├── *.topic.Escalate     ← deterministic flow
      ├── *.topic.<custom>     ← any custom topics
      ├── *.settings.Ivr       ← voice font, speaking speed, IVR-level config
      └── *.action.<connector> ← connector / tool wiring

— at runtime —

msdyn_liveworkstream    routes calls to →   msdyn_omnichannelqueue
                                                  ↓
                                          msdyn_ocliveworkitem  (the "live call" record)
                                                  ↓
                                          msdyn_ocsession  (one row per agent-leg of the call)
                                                  ↓
                                          conversationtranscript  (the JSON activity log, lands ~1-5min late)
```

Carry this picture in your head: **edits go into `botcomponent`, runtime evidence comes out of `msdyn_ocliveworkitem` and `conversationtranscript`**. Everything else in this skill is detail on top of those two flows.

---

## 5. Mental model — how a realtime voice turn actually works

Understanding this is the difference between fixing a bug in five minutes and chasing your tail for a day.

### 5.1. The turn

A "turn" is one round-trip from caller speech to bot speech (or to a topic-driven action). On every turn the **generative orchestrator** receives:

1. The transcribed user utterance (from the speech-to-text layer).
2. The current state of all tools the agent has access to (their descriptions and signatures).
3. The list of topics and their `triggerQueries` (the canonical example phrases that should trigger each topic).
4. The full GPT instructions (the `gpt.default` YAML) plus the running conversation history.

It then produces a **plan** consisting of zero or more steps:

- `DynamicPlanStepTriggered` → invoke a specific tool (e.g. `create_record` on the Dataverse MCP) **or** a specific topic (e.g. `Escalate`).
- `DynamicPlanStepFinished` → the step returned.
- Optionally followed by the orchestrator generating speech via the GPT (if no topic ran, OR if a topic ran but a follow-up utterance is needed).

The plan is what you see in the transcript as the `DynamicPlan*` event stream. If you understand the plan, you understand the call.

### 5.2. The single most important behavioural fact

> **The realtime model cannot truly "stay silent" on a user turn.** If it does not invoke a topic or tool, it will generate speech. So your GPT instructions must always say *what to do*, never just *what not to do*.

This is why the classic anti-pattern of *"stay silent when the caller asks for a human"* doesn't work. You have to instead tell the model *"invoke the Escalate topic, the topic owns the speech"*. The model has to do **something** with the turn — silence is not a thing it can do unless a topic is firing.

### 5.3. The orchestrator's "wake-up" model

The orchestrator runs on **user turns**, not on the wall clock. This means:

- If a tool takes 5 seconds to return, those 5 seconds are silent on the line unless the GPT was told to emit a filler before/during the dispatch.
- After a tool returns, the orchestrator does NOT automatically run again. It produces the response that was queued behind the tool call, then waits for the next user turn.
- If your GPT instructions don't queue a follow-up reply after the tool call, the bot will go silent and the caller will have to say *"are you still there?"* to wake the planner up.

This is the **#1 source of perceived poor quality on realtime voice agents** and it is invisible if you only test in the Copilot Studio web test pane (which is text-based and doesn't expose latency).

### 5.4. Three layers, three failure modes

When a call goes wrong, identify which layer failed **before** editing anything:

| Layer | Common failure | First thing to check |
|---|---|---|
| **Orchestrator chose wrong action** | GPT speaks something generic when a topic should have fired | `msdyn_ocliveworkitem.msdyn_transfercount` (0 = no topic fired); `conversationtranscript` activities for the `DynamicPlanStepTriggered` event |
| **Routing sent it to wrong queue / no queue** | Topic fired but call sits forever | `msdyn_ocliveworkitem.msdyn_cdsqueueid`; `msdyn_workstreamworkdistributionmode` |
| **Tool/connector failed** | Tool dispatch happened but returned an error or nothing | `DynamicPlanStepFinished` event payload in transcript; the F6 note on the case (if a case was created) |

You will save hours by always running this triage before opening Copilot Studio.

---

## 6. Discovering the assets for an agent you are about to work on

If you are picking up an agent for the first time, or working in a new tenant, you need three GUIDs: the bot ID, the `gpt.default` botcomponent ID, and the bot's schema name (the prefix on every component, e.g. `<your_agent_schemaname>`). Here is the discovery script:

```pwsh
$env_ = 'https://<orgname>.crm<region>.dynamics.com'
$tok  = az account get-access-token --resource $env_ --query accessToken -o tsv
$h    = @{ Authorization="Bearer $tok"; Accept='application/json' }

# 1. List all bots in the env (filter by name if you know it)
(Invoke-RestMethod -Uri "$env_/api/data/v9.2/bots?`$select=botid,name,schemaname,statecode&`$filter=statecode eq 0" -Headers $h).value |
  Format-Table name, botid, schemaname

# 2. Once you know the bot's schemaname (e.g. <your_agent_schemaname>), list its botcomponents
$schema = '<your_agent_schemaname>'
(Invoke-RestMethod -Uri "$env_/api/data/v9.2/botcomponents?`$select=botcomponentid,name,schemaname,componenttype&`$filter=startswith(schemaname,'$schema.')" -Headers $h).value |
  Sort-Object schemaname | Format-Table schemaname, componenttype, botcomponentid

# 3. Identify the key components by schemaname suffix:
#    *.gpt.default   → componenttype 15 → THE big system prompt
#    *.topic.<Name>  → componenttype 9  → topics
#    *.settings.Ivr  → componenttype 18 → IVR / voice config
```

Save the discovered GUIDs at the top of a `voice-agent.config.ps1` (or in the workspace `copilot-instructions.md`) so you never have to look them up again. Example template:

```pwsh
$env_      = 'https://<your-org>.crm.dynamics.com'
$botId     = '<your-bot-id>'
$schema    = '<your_agent_schemaname>'
$gptId     = '0375ba5d-83da-4a8b-ad1d-d79a8be55d99'   # botcomponent for *.gpt.default
```

---

## 7. The canonical seven-step iteration loop

Every meaningful change to a voice agent follows the same loop. Internalise this — it is the rhythm of the work.

1. **PULL** the current `gpt.default` (or topic) YAML out of Dataverse to a local file. This guarantees you are editing the live version, not a stale local copy.
2. **EDIT** the local file. Use diff-friendly edits — replace named blocks, don't restructure the whole file unless you have to.
3. **PATCH** the file back into `botcomponent.data`. The PATCH is silent — there is no compile error, no schema check at this stage. Bad YAML will only surface at publish or at call time.
4. **PUBLISH** with `pac copilot publish --bot <botId>`. This is what actually makes the change visible to live callers. Without publish, the PATCH is dormant.
5. **VERIFY** by re-pulling the YAML and checking your version marker (you DO put a `# Version: vN — date — what changed` line at the top, don't you?) and re-checking the `botcomponent.modifiedon` and the publish timestamp.
6. **TEST** by placing a real voice call. There is no shortcut. The Copilot Studio web test pane will not reproduce latency, speech-to-text errors, or barge-in behaviour.
7. **ANALYSE** the resulting `conversationtranscript`. Find the issue, return to step 1.

A round trip is typically 2-3 minutes once the snippets are at your fingertips, with the transcript itself appearing 1-5 minutes after you hang up.

> **Critical timing note**: The `conversationtranscript` row does NOT exist immediately. Dataverse persists it after the call wraps up — typically within 1-2 minutes for short calls, up to 10 minutes for longer ones. Always *poll* for the new transcript rather than assuming it's there. See §10 for the polling pattern.

---

## 8. Editing the agent — the `gpt.default` workflow in detail

The GPT instructions are a single YAML document stored in `botcomponent.data` as a string. They look something like this (truncated):

```yaml
kind: GptComponentMetadata
instructions: |-
  # <Your Agent Name> — <Your Use Case> Voice Agent
  # Version: v10 — 2026-05-15 — silence-gap UX fix
  ...
  ## R1. ESCALATION HANDOFF (HIGHEST PRIORITY)
  ...
gptCapabilities:
  webBrowsing: false
aISettings:
  model:
    modelNameHint: GPT5Chat
```

A few things to notice and respect:

- **The `instructions:` value is the only thing you should edit.** Do not touch `gptCapabilities` or `aISettings` from the Web API unless you know exactly what you are doing — those are managed by Copilot Studio.
- **The leading `|-` is significant.** It means YAML block scalar with newline-stripped trailing. Preserve it. Switching to `|` or `>` will subtly change the prompt's whitespace and confuse the orchestrator.
- **Indentation matters.** Every line of the instructions is indented by two spaces. If you accidentally dedent a section by one space, the YAML is still valid but the orchestrator may not see your changes correctly.
- **Always keep a version marker** at the top of the instructions, e.g. `# Version: v10 — 2026-05-15 — silence-gap UX fix`. This is the single best diagnostic: when you pull the YAML and see the version, you know instantly what's live.

### 8.1. The pull step

```pwsh
$tok = az account get-access-token --resource $env_ --query accessToken -o tsv
$h   = @{ Authorization="Bearer $tok"; Accept='application/json' }
$r   = Invoke-RestMethod -Uri "$env_/api/data/v9.2/botcomponents($gptId)?`$select=data,name,schemaname,modifiedon" -Headers $h
"name=$($r.name) modified=$($r.modifiedon) bytes=$($r.data.Length)"
$r.data | Out-File "$env:TEMP\gpt-default-current.yaml" -Encoding utf8 -NoNewline
```

The `-NoNewline` is essential. Otherwise PowerShell appends a CRLF that will round-trip into Dataverse and accumulate stray blank lines over time.

### 8.2. The edit step

Open the local YAML in your editor. **Make small, named edits**, not wholesale rewrites. The single most reliable pattern is:

- **Rules** are numbered `R1, R2, R3, …` and are priority directives.
- **Flow steps** are numbered `F1, F2, F3, …` and describe the per-turn dialogue.
- **NEVER DO** is a final `R<n>` block listing absolute prohibitions.

If you add a new rule, give it the next number. If you change a rule, increment your version marker. If you renumber rules, do it deliberately and note it in the version comment.

When you edit through a coding agent like GitHub Copilot, prefer **targeted string replacement** (with 3-5 lines of context before and after) over rewriting the whole file. This keeps diffs reviewable and avoids accidental indentation drift.

### 8.3. The PATCH step

```pwsh
$tok  = az account get-access-token --resource $env_ --query accessToken -o tsv
$h    = @{ Authorization="Bearer $tok"; 'Content-Type'='application/json'; 'If-Match'='*' }
$yaml = Get-Content "$env:TEMP\gpt-default-current.yaml" -Raw
$body = @{ data = $yaml } | ConvertTo-Json -Compress -Depth 5
Invoke-RestMethod -Uri "$env_/api/data/v9.2/botcomponents($gptId)" -Method Patch -Headers $h -Body $body
```

Notes:
- `If-Match: *` accepts the row regardless of ETag — fine for single-author editing. If you have a team and concurrent edits are possible, capture the ETag from the GET response and pass that instead.
- The `data` value must be a string (the raw YAML). `ConvertTo-Json` escapes embedded quotes and newlines automatically.
- A successful PATCH returns 204 No Content — `Invoke-RestMethod` returns nothing on success. Silence is good.

Then **immediately verify** by re-pulling and grepping for your version marker:

```pwsh
$r = Invoke-RestMethod -Uri "$env_/api/data/v9.2/botcomponents($gptId)?`$select=data,modifiedon" -Headers @{Authorization="Bearer $tok"; Accept='application/json'}
"Server bytes=$($r.data.Length) modified=$($r.modifiedon)"
if ($r.data -match 'Version: v10') { 'v10 live in Dataverse' } else { 'v10 NOT live — PATCH failed silently' }
```

### 8.4. The publish step

```pwsh
pac copilot publish --bot $botId
```

Output should end with `Published successfully!`. If it doesn't, do not test — the live behaviour is whatever was published before your PATCH. Common publish failures:

- *"You are not signed in"* → `pac auth list`, `pac auth select --name <profile>`.
- *"Bot not found"* → wrong `botId` for the selected env. Switch profile.
- *"Validation error in topic X"* → your YAML is invalid. The error usually points to the line. Fix and PATCH again.

Publishing takes 10-60 seconds depending on environment size. Wait for completion before placing a test call.

### 8.5. Editing a topic (not the GPT instructions)

Topics live in the same `botcomponent` table but with `componenttype = 9` and a schema name like `<your_agent_schemaname>.topic.Escalate`. The data column is a different YAML schema (`kind: AdaptiveDialog`). The same pull → edit → PATCH → publish loop applies.

When working on a topic, the two fields you most often touch are:

- `triggerQueries`: an array of example user phrases that trigger the topic. **Add aggressive coverage** — the realtime orchestrator does not generalise as well as you'd think. If a caller says *"can I speak to a person"* and your only trigger is *"transfer me to an agent"*, it may not fire.
- `intent.includeInOnSelectIntent`: set to `true` so the generative orchestrator can pick this topic as an action even when it's choosing between actions (not just matching trigger phrases).

Both of these changes are described in the companion `copilot-studio-voice-agent` skill (`§ Escalation triggers`); read that for the canonical Escalate-topic fix.

### 8.6. Editing safely from a Copilot agent (this assistant)

When you ask GitHub Copilot to make a change to the YAML:

1. Have it **pull the live YAML first** into `$env:TEMP\<bot>-current.yaml`. Never trust a cached copy.
2. Use **string-replace edits** with surrounding context (the agent has tooling for this).
3. Have it **diff against the previous version** in chat before patching.
4. PATCH and publish.
5. Have the agent **re-pull** and verify the version marker landed.
6. The agent should **stop and ask before testing** — only a human can place the test call.

This protocol prevents an agent from silently corrupting a 28KB YAML file in a way that bricks the live agent.

---
## 9. Forensic analysis of the running agent (Dataverse runtime tables)

When a call has just happened — or is happening right now — the live state lives in three Omnichannel tables. Knowing how to query them tells you whether topics fired, where the call was routed, who picked it up, and (often) what went wrong.

### 9.1. `msdyn_ocliveworkitem` — one row per live conversation

This is the closest thing to a "call summary" record. It is updated in near real-time. The columns that matter most:

| Column | Meaning |
|---|---|
| `msdyn_title` | Caller display name or "Unknown" |
| `msdyn_transfercount` | Number of topic-driven transfers attempted. **0 means no topic-driven escalation fired**. |
| `msdyn_escalationcount` | Number of escalations to a human queue. Typically `transfercount == escalationcount` for human handoffs. |
| `_msdyn_activeagentid_value` | The user/bot currently assigned. If this is still the bot user GUID, the call never transferred. |
| `_msdyn_cdsqueueid_value` | The queue the work item is sitting in. Cross-reference with `msdyn_omnichannelqueue` to confirm it's the queue you expected. |
| `msdyn_statuschangereason` | Free-form. Common values: `CustomerDisconnectedOrLeftActiveConversation`, `AgentEndedTheConversation`. |
| `statecode` / `statuscode` | Active vs. closed work item. |
| `createdon` / `modifiedon` | Use to find recent calls. |

### 9.2. Canonical "last 5 calls" query

```pwsh
$tok = az account get-access-token --resource $env_ --query accessToken -o tsv
$h   = @{ Authorization="Bearer $tok"; Accept='application/json'; Prefer='odata.include-annotations="*"' }
$select = 'msdyn_title,msdyn_transfercount,msdyn_escalationcount,_msdyn_activeagentid_value,_msdyn_cdsqueueid_value,msdyn_statuschangereason,statecode,createdon,modifiedon'
(Invoke-RestMethod -Uri "$env_/api/data/v9.2/msdyn_ocliveworkitems?`$select=$select&`$orderby=modifiedon desc&`$top=5" -Headers $h).value |
  Format-Table createdon, msdyn_title, msdyn_transfercount, msdyn_escalationcount, '_msdyn_activeagentid_value@OData.Community.Display.V1.FormattedValue', msdyn_statuschangereason -AutoSize
```

The `@OData.Community.Display.V1.FormattedValue` annotations give you the human-readable display values alongside the GUIDs — the `Prefer` header is what unlocks them.

### 9.3. Interpreting the output

Five common patterns and what they mean:

| `transfercount` | `escalationcount` | `activeagentid` | Interpretation |
|---|---|---|---|
| 0 | 0 | bot user | Call never transferred. Either the caller never asked for a human OR the Escalate topic didn't fire when they did. Cross-check with the transcript. |
| ≥1 | ≥1 | a human user | Escalation worked. The active agent is whoever picked up the toast. |
| ≥1 | 0 | bot user | Topic fired but didn't escalate (e.g. transfer to another bot). Rare. |
| 0 | 0 | bot user, `CustomerDisconnectedOrLeftActiveConversation` | Caller hung up before anything interesting happened. |
| ≥1 | ≥1 | bot user | Escalation attempted but no human picked up — call is sitting in queue. Check `cdsqueueid` and agent presence. |

### 9.4. `msdyn_ocsession` — one row per agent leg

For a call that was escalated, there are multiple `msdyn_ocsession` rows — one for the bot's leg, one (or more) for each human agent that handled it. Join by `_msdyn_ocliveworkitemid_value`.

```pwsh
$liveItemId = '<guid from §9.2>'
$sel = 'msdyn_sessionnumber,_msdyn_agentid_value,createdon,modifiedon,statecode'
(Invoke-RestMethod -Uri "$env_/api/data/v9.2/msdyn_ocsessions?`$filter=_msdyn_ocliveworkitemid_value eq $liveItemId&`$select=$sel&`$orderby=createdon" -Headers $h).value |
  Format-Table createdon, msdyn_sessionnumber, '_msdyn_agentid_value@OData.Community.Display.V1.FormattedValue', statecode -AutoSize
```

If you see only one session and it's the bot, escalation didn't take. If you see two, the bot handed off cleanly.

### 9.5. Cases created by the bot in this conversation

To prove the bot actually wrote the case it claimed to:

```pwsh
$h2 = @{ Authorization="Bearer $tok"; Accept='application/json'; Prefer='odata.include-annotations="*"' }
$f = "createdon ge 2026-05-15T13:00:00Z"  # bracket the time window of the call
(Invoke-RestMethod -Uri "$env_/api/data/v9.2/incidents?`$select=ticketnumber,title,description,createdon,_createdby_value,_subjectid_value&`$filter=$f&`$orderby=createdon desc&`$top=5" -Headers $h2).value |
  Format-Table createdon, ticketnumber, title, '_subjectid_value@OData.Community.Display.V1.FormattedValue' -AutoSize
```

Look at the title (sentence case? brand preserved?) and the description (prefixed `[Voice Agent v10]`? matches the conversation?) to confirm the agent did the right thing.

### 9.6. Notes attached to the case

Every case the agent creates (in this workspace at least) gets an `annotation` row with the conversation summary — KB lookups, satisfaction outcome, tool errors. Fetch them:

```pwsh
$caseId = '<incidentid GUID>'
(Invoke-RestMethod -Uri "$env_/api/data/v9.2/annotations?`$filter=_objectid_value eq $caseId&`$select=subject,notetext,createdon" -Headers @{Authorization="Bearer $tok"; Accept='application/json'}).value |
  ForEach-Object { "--- $($_.createdon) — $($_.subject) ---"; $_.notetext }
```

These notes are **gold** for debugging — they show you what the agent *thought* happened on the call from its own perspective. Mismatches between the note and the transcript usually mean the GPT instructions are confusing the model about what it just did.

### 9.7. Workflow / process state — the classic-workflow trap

A classic XAML workflow (e.g. an auto-acknowledgement email triggered on case create) shows up as **two rows** in the `workflow` table when activated: `type = 1` (Definition) and `type = 2` (Activation) linked by `parentworkflowid`. Both show `statecode = Activated`. This looks like a duplicate but it is normal D365 behaviour — only the Activation actually fires.

```pwsh
(Invoke-RestMethod -Uri "$env_/api/data/v9.2/workflows?`$select=workflowid,name,type,statecode,_parentworkflowid_value&`$filter=contains(name,'Case Acknowledgement')" -Headers @{Authorization="Bearer $tok"; Accept='application/json'}).value |
  Format-Table name, type, statecode, _parentworkflowid_value -AutoSize
```

If you see two rows with `type = 1` and `type = 2`, that is one workflow. If you see two rows both with `type = 1`, you have actual duplicates and should deactivate one.

> **Important**: Classic workflows cannot be deactivated via Web API PATCH (returns `Cannot update a workflow activation`) and they don't respond to the `Microsoft.Dynamics.CRM.SetState` action (404). They must be edited via the designer in Dataverse / make.powerapps.com.

---
## 10. Forensic conversation analysis (the `conversationtranscript` table)

This is the most powerful diagnostic capability in the skill. A `conversationtranscript` row contains the **entire** activity stream of a call as a JSON blob in the `content` column — every user utterance with millisecond timestamps, every bot utterance, every plan dispatch, every tool result, every event. Once you can parse this, you can answer almost any question about what happened on a call.

### 10.1. What's in the JSON

The `content` field decodes to an object like:

```json
{
  "$schema": "...",
  "activities": [
    {
      "type": "event",
      "name": "startConversation",
      "timestampMs": 1747314460700,
      ...
    },
    {
      "type": "message",
      "from": { "role": 0, "id": "bot" },
      "text": "Hello, Chris Walker, you're through to Contoso customer support…",
      "timestampMs": 1747314460700,
      ...
    },
    {
      "type": "event",
      "name": "DynamicPlanReceived",
      "timestampMs": 1747314538400,
      "value": { "ask": "Can you create a case for me…?" }
    },
    {
      "type": "event",
      "name": "DynamicPlanStepTriggered",
      "timestampMs": 1747314538400,
      "value": { "taskDialogId": "MCP:…:create_record" }
    },
    {
      "type": "event",
      "name": "DynamicPlanStepFinished",
      "timestampMs": 1747314543600,
      "value": { "taskDialogId": "MCP:…:create_record" }
    }
  ]
}
```

Key fields:

- `type`: `"message"` for spoken utterances, `"event"` for orchestrator events.
- `from.role`: `0` = bot, anything else = user (typically a numeric ID for the caller).
- `timestampMs`: Unix epoch milliseconds. Convert to local time with `(Get-Date '1970-01-01').AddMilliseconds($ms).ToLocalTime()`.
- `name` (on events): the most informative are `startConversation`, `DynamicPlanReceived` (a new user turn arrived), `DynamicPlanReceivedDebug` (carries the orchestrator's parsed `ask`), `DynamicPlanStepTriggered` (plan dispatched), `DynamicPlanStepFinished` (plan returned), `DynamicPlanFinished` (whole plan done).
- `value.taskDialogId`: for plan steps, identifies the tool or topic — e.g. `MCP:…:create_record`, `<your_agent_schemaname>.topic.Escalate`, `P:BotHangupTool`.

### 10.2. The polling pattern (wait for the transcript to land)

After a test call, the transcript is NOT immediately available. The persistence pipeline can take anywhere from a few seconds to ten minutes depending on system load. The right approach is to **poll, with a baseline**.

```pwsh
$tok = az account get-access-token --resource $env_ --query accessToken -o tsv
$h   = @{ Authorization="Bearer $tok"; Accept='application/json' }

# 1. Capture the baseline — the IDs of all transcripts that already exist BEFORE your test call.
$baseline = (Invoke-RestMethod -Uri "$env_/api/data/v9.2/conversationtranscripts?`$top=20&`$orderby=createdon desc&`$select=conversationtranscriptid" -Headers $h).value.conversationtranscriptid

# 2. Now place the test call. Hang up.

# 3. Poll for a new transcript with a substantive (> 5KB) content body.
for ($i=1; $i -le 30; $i++) {
  $list = (Invoke-RestMethod -Uri "$env_/api/data/v9.2/conversationtranscripts?`$top=5&`$orderby=createdon desc&`$select=conversationtranscriptid,createdon,conversationstarttime" -Headers $h).value
  $new = $list | Where-Object { $baseline -notcontains $_.conversationtranscriptid }
  "[$i $(Get-Date -Format HH:mm:ss)] new=$($new.Count)"
  foreach ($n in $new) {
    $r = Invoke-RestMethod -Uri "$env_/api/data/v9.2/conversationtranscripts($($n.conversationtranscriptid))?`$select=content" -Headers $h
    if ($r.content.Length -gt 5000) {
      $r.content | Out-File "$env:TEMP\transcript-latest.json" -Encoding utf8 -NoNewline
      "saved id=$($n.conversationtranscriptid) bytes=$($r.content.Length)"
      return
    }
  }
  Start-Sleep -Seconds 30
}
```

Why the `> 5KB` filter? Empty or aborted conversations produce tiny stub transcripts (~800 bytes). You almost always want the substantive one. Adjust the threshold for your use case.

### 10.3. The timeline dump — the single most useful one-liner

This is the dump pattern I use on every test call. Paste, run, read.

```pwsh
$j = Get-Content "$env:TEMP\transcript-latest.json" -Raw | ConvertFrom-Json
"Activities: $($j.activities.Count)"
$j.activities | ForEach-Object {
  $t = if ($_.timestampMs) { (Get-Date '1970-01-01').AddMilliseconds($_.timestampMs).ToLocalTime().ToString('HH:mm:ss.f') } else { '--' }
  if ($_.type -eq 'message') {
    $text = $_.text -replace "`r"," " -replace "`n"," "
    if ($text.Length -gt 300) { $text = $text.Substring(0,300)+'...' }
    $who = if ($_.from.role -eq 0) { 'BOT ' } else { 'USER' }
    "[$t] $who $text"
  } elseif ($_.type -eq 'event') {
    $val = ''
    if ($_.value -and $_.value.ask)         { $val = "ask='$($_.value.ask)'" }
    elseif ($_.value -and $_.value.taskDialogId) { $val = $_.value.taskDialogId }
    "[$t] EVT/$($_.name) $val"
  }
}
```

You get back something like:

```
[14:48:50.9] USER I'm trying to troubleshoot one of your Voltage EV chargers.
[14:48:55.8] USER Can you create a case for me, please?
[14:48:58.4] EVT/DynamicPlanReceived
[14:48:58.4] EVT/DynamicPlanReceivedDebug ask='Can you create a case for me?'
[14:48:58.4] EVT/DynamicPlanStepTriggered MCP:...create_record
[14:49:03.6] EVT/DynamicPlanStepFinished MCP:...create_record
[14:49:07.4] BOT  Thanks for your patience—I'm working on logging that case…
[14:49:10.9] USER Hello, are you still there?
[14:49:39.0] BOT  Apologies for the delay—I'm finalizing the details…
[14:49:42.1] BOT  Your case has been logged. We'll be in touch on your number ending nine-two-five-six…
```

Now you can SEE the call. Read it left to right, eyeball the gaps between timestamps.

### 10.4. Measuring silent gaps

The most common voice-quality issue is dead air. To find it, scan the timeline for any gap of more than ~3 seconds between consecutive BOT utterances or between a `DynamicPlanStepFinished` and the next BOT utterance. In the example above:

- `14:48:55.8` user finishes → `14:48:58.4` plan dispatched (2.6s — orchestrator planning latency, normal).
- `14:48:58.4` plan dispatched → `14:49:03.6` plan finished (5.2s — tool call latency).
- `14:49:03.6` plan finished → `14:49:07.4` first BOT speech (**3.8s of post-tool silence — bad**).
- `14:49:11.0` BOT speaks → `14:49:39.0` next BOT speech (**28s gap — very bad; the caller had to say "are you still there?" to wake the planner**).

These two gaps are exactly the kind of UX bug the conversation forensic surfaces and the GPT-instructions don't tell you about until you look at the data. The fix lives in the GPT instructions (pre-dispatch acknowledgement + immediate post-tool readback rule); see §11.

### 10.5. Cross-referencing transcript with the case it created

Once you know a case GUID (from §9.5), confirm the transcript shows the matching `create_record` plan finish, and confirm the case fields match what the bot read back to the caller. Mismatches mean either the GPT instructions are confused (model said "logged it" but no tool fired) OR the tool failed silently (plan finished but with an error payload — look at the full `value` object of `DynamicPlanStepFinished`).

### 10.6. When the transcript is incomplete

Some transcripts end abruptly mid-call. Common causes:

- **Escalation handoff** — when the call leaves the bot for a human, the bot's transcript stops there. The human's leg is in a separate transcript (or sometimes in the same `msdyn_ocliveworkitem` but a different `msdyn_ocsession`).
- **Tool error mid-plan** — the orchestrator can crash a turn if a tool returns malformed data. Look for missing `DynamicPlanFinished` events.
- **Caller disconnected** — the transcript ends with no `BotHangupTool` event.

If you see a 23-activity transcript that ends on `DynamicPlanFinished` for `Escalate` and you were expecting case-creation activity, the call escalated before getting to the case — search for a *separate* transcript that handles the case-creation leg.

---
## 11. Pattern library — the bugs you will see, and how to fix them

This is the accumulated wisdom from real iterative tuning. Each entry has the symptom, the diagnostic path, and the GPT-instructions fix.

### 11.1. Escalation doesn't fire when the caller asks for a human

- **Symptom**: Caller says *"can I speak to a human"* (or any variant) and the bot replies *"of course, I'll transfer you"* but never actually transfers. `msdyn_ocliveworkitem.msdyn_transfercount = 0`.
- **Root cause**: The Escalate topic's `triggerQueries` doesn't cover the exact phrase the caller used, and the GPT instructions tell the model to "stay silent" rather than to "invoke Escalate". Realtime models can't stay silent — if no topic fires, they speak.
- **Fix in the Escalate topic YAML**: Expand `triggerQueries` aggressively — *speak to / talk to / connect me to / put me through to / transfer me to + a person / human / agent / representative / manager / someone*, plus *escalate*, *I want a human*, *get me a human*, *call me back*. Set `intent.includeInOnSelectIntent: true`.
- **Fix in the GPT instructions (`gpt.default`)**: Replace any "stay silent on escalation" wording with the explicit directive *"you MUST invoke the Escalate topic and produce NO spoken output"*. Tell the model what to do, not what not to do.

### 11.2. Silent gap during a tool call (perceived poor quality)

- **Symptom**: Caller asks for something that requires a tool call (e.g. *"create a case for me"*). Bot goes silent for 5-15 seconds. Caller says *"hello, are you still there?"*. Eventually bot speaks.
- **Root cause**: GPT instructions told the model to silently dispatch the tool ("the confirmation read-back trains the caller to wait silently"). In practice, the orchestrator takes 2-3 seconds to plan, the tool takes 3-7 seconds to return, the model takes another 1-3 seconds to compose the success message. That's 6-13 seconds of total silence.
- **Fix**: In the F-step that triggers the tool, mandate:
  1. A **confirmation read-back** BEFORE dispatch (e.g. *"Just to confirm, I'll log this as: <summary>. Shall I go ahead?"*). The read-back itself fills 3-4 seconds of audio.
  2. A **pre-dispatch acknowledgement** AFTER the caller's "yes" and IN THE SAME RESPONSE as the tool dispatch (e.g. *"Right, let me get that logged for you now."*). Fills the 2-3s planner gap.
  3. An **immediate post-tool readback** rule: as soon as the tool returns, the very next utterance MUST be the success line. No "we're just about done" fillers after the tool has returned.
- This is the v10 fix verified in real-world iterative tuning — see your own version-control diff after applying the pattern.

### 11.3. Bot creates a duplicate case

- **Symptom**: One conversation, two cases.
- **Root cause**: The caller said something post-confirmation that the orchestrator interpreted as a new request to log a case (e.g. *"are you still there?"* re-triggered the planner, which re-evaluated the conversation and re-dispatched `create_record`).
- **Fix**: An idempotency rule in the GPT instructions:
  > *"Once you have invoked `create_record` for an incident in this conversation AND received a successful response (a case GUID), you MUST NOT invoke `create_record` again for an incident in the same call. If the caller asks 'is it done?' / 'are you still there?', reassure verbally only."*
- Verify by re-running the timeline dump and confirming only ONE `DynamicPlanStepTriggered` for `create_record`.

### 11.4. Title case is wrong (ALL CAPS or all lowercase)

- **Symptom**: Case title in the database is `broken smart meter` or `BROKEN SMART METER` instead of `Broken smart meter`.
- **Root cause**: The model echoes the speech-to-text output verbatim into the `title` field. STT may output ALL CAPS for emphatic speech or lowercase otherwise.
- **Fix**: A title-casing rule in F5:
  > *"Title MUST be SENTENCE CASE: capitalise first letter, lowercase the rest, EXCEPT preserve canonical brand names exactly (VoltEdge, SunWeave, ThermaSmart, PowerCell, SmartFlow, Contoso, MFA, EV, kWh, …). Examples: STT 'BROKEN SMART METER' → title 'Broken smart meter'; STT 'my voltedge keeps tripping' → title 'VoltEdge keeps tripping'."*

### 11.5. Email subject is jammed against bracket

- **Symptom**: Auto-acknowledgement email subject reads `broken smart meter[Case Number:CAS-02016-R7F2D9]` (no space).
- **Root cause**: The classic-workflow email template's XSL subject doesn't include a separating space around the bracket.
- **Fix**: Edit the `templates` row directly (the XSL is in `subject`, the form display in `subjectpresentationxml`). Insert ` [Case Number: ` (leading space + post-colon space). Note: classic workflows fire on the template; updating the template is sufficient.

### 11.6. Subject record visible in the Subject tree but hidden in Customer Service admin

- **Symptom**: You created a subject via Web API. It appears in the `subjects` table but doesn't show up in the Customer Service Admin Center subject hierarchy.
- **Root cause**: New subjects created via Web API have `featuremask = NULL`. The admin UI treats NULL as hidden.
- **Fix**: Always PATCH `featuremask = 1` on new subjects:
  ```pwsh
  Invoke-RestMethod -Uri "$env_/api/data/v9.2/subjects($subjectId)" -Method Patch -Headers @{Authorization="Bearer $tok"; 'If-Match'='*'; 'Content-Type'='application/json'} -Body '{"featuremask":1}'
  ```
- Or include it in the original create payload.

### 11.7. "Duplicate" classic workflow — false alarm

- **Symptom**: You see two `workflow` rows with the same name in the `workflow` table.
- **Diagnosis**: Check the `type` column. `type = 1` is the Definition (the editable source). `type = 2` is the Activation (the runtime). When a workflow is activated, both exist; they are linked by `parentworkflowid`. Only the Activation fires.
- **Fix**: Nothing to fix — this is normal. Confirm with the join: `_parentworkflowid_value` on the Activation should point at the Definition.

### 11.8. Bad-audio incoherent input handled as a real request

- **Symptom**: Speech-to-text misheard the caller (line noise, accent, mumble) and produced an incoherent transcription. The bot confidently acted on it — e.g. invoked `create_record` with junk data, or thanked the caller for nothing.
- **Fix**: An incoherent-input rule with a coherence test:
  > *"Before responding, judge whether the utterance is COHERENT. An utterance is INCOHERENT if (a) it contains NO domain term AND (b) it is NOT a clear social/control phrase. On INCOHERENT input: 1st occurrence → 'Sorry, I didn't quite catch that — could you say it again?'; 2nd → offer transfer; 3rd → invoke Escalate. Never invoke any tool from an incoherent utterance."*
- Plus a **phonetic alias** table — silently normalise common STT mishears (`vault edge` → `VoltEdge`, `power sell` → `PowerCell`, `small meter` → `smart meter`, etc.).

### 11.9. Bot says "thank you" to a single noise word

- **Symptom**: Caller says *"brains"* (noise) and the bot replies *"You're welcome!"*.
- **Root cause**: The model is matching on tone, not on lexical content.
- **Fix**: An explicit rule:
  > *"Never invoke ThankYou unless the LITERAL substring 'thank', 'thanks', 'cheers', or 'appreciate' appears in the caller's text. Single noise words ('brains', 'great', 'right') are NOT thanks."*

### 11.10. Bot hangs up on a single short word

- **Symptom**: Mid-conversation, caller says *"ok"* and the bot delivers the closing line.
- **Fix**:
  > *"Do NOT invoke `BotHangupTool` on a single short word UNLESS your previous turn was a hangup-context question ('Anything else?') AND the reply is clearly negative. Otherwise confirm once: 'Did you mean to end the call, or is there something else?'"*

---
## 12. Best practices

Distilled from many iteration cycles. Adopt all of these and your agents will be measurably more robust.

1. **Version every prompt change.** Bump a `# Version: vN — date — what changed` marker at the top of `gpt.default`. Also bump the `[Voice Agent vN]` prefix used in case descriptions. Then you can grep for it in Dataverse and on disk.
2. **Pull before you edit, every time.** Never trust a local YAML copy that's more than a few minutes old. Someone (you, a colleague, the UI) may have changed the live version.
3. **Publish is not automatic.** A PATCH to `botcomponent.data` is dormant until `pac copilot publish` succeeds. Always publish, always wait for the success line.
4. **Tell the model what to do, not what not to do.** Realtime models can't "stay silent" — they must invoke a topic, call a tool, or speak. Negative constraints alone produce confused behaviour.
5. **Mandate phrasing for critical lines.** Greeting, satisfaction check, success readback, close — write `Say EXACTLY: "<line>"`. Otherwise the model drifts.
6. **Throttle fillers, don't ban them.** Banning all fillers produces dead air. Allow one filler per tool call, with a 15s gap before a second.
7. **Use idempotency rules for any state-changing tool.** Realtime orchestrators will happily re-dispatch a `create_record` if the caller's next turn is ambiguous. Explicitly forbid second invocations per call.
8. **Always test on real audio.** The Copilot Studio web test pane is text-only and lies about voice behaviour (latency, barge-in, STT errors).
9. **Always read the transcript after the test.** "It seemed to work" is not data. The timeline dump in §10.3 is.
10. **Commit your YAML to git.** Even though it lives in Dataverse, keep a copy in the workspace under source control. Then you can diff vN against vN+1 in seconds.
11. **One change per iteration.** It is tempting to bundle three fixes into one PATCH. Don't — when something regresses you won't know which change caused it.
12. **Save TEMP transcripts with a versioned name.** `$env:TEMP\transcript-v10-test1.json` not `transcript.json`. You will refer back to old transcripts more often than you expect.
13. **Document the Definition+Activation pattern in your team wiki** before someone "fixes" a duplicate classic workflow that wasn't actually a duplicate.
14. **Cross-reference the case with the transcript** every time. Read the case title, the description, and the F6 note. Compare with what the bot said in the transcript. Mismatches are bugs.
15. **Watch for STT misheards as a class of bug.** Maintain a phonetic alias table and update it whenever you hear a new mishear in a test call.

---

## 13. Reference snippets — copy/paste blocks

### 13.1. The "standard header" — paste at the top of every PowerShell session

```pwsh
$env_   = 'https://<your-org>.crm.dynamics.com'
$botId  = '<your-bot-id>'
$schema = '<your_agent_schemaname>'
$gptId  = '0375ba5d-83da-4a8b-ad1d-d79a8be55d99'
$tok    = az account get-access-token --resource $env_ --query accessToken -o tsv
$h      = @{ Authorization="Bearer $tok"; Accept='application/json' }
$hFmt   = @{ Authorization="Bearer $tok"; Accept='application/json'; Prefer='odata.include-annotations="*"' }
```

### 13.2. Pull → edit-cycle → patch → publish (single function)

```pwsh
function Pull-Gpt {
  param([string]$Path = "$env:TEMP\gpt-default-current.yaml")
  $r = Invoke-RestMethod -Uri "$env_/api/data/v9.2/botcomponents($gptId)?`$select=data,modifiedon" -Headers $h
  $r.data | Out-File $Path -Encoding utf8 -NoNewline
  "pulled bytes=$($r.data.Length) modified=$($r.modifiedon) → $Path"
}

function Patch-Gpt {
  param([string]$Path = "$env:TEMP\gpt-default-current.yaml")
  $yaml = Get-Content $Path -Raw
  $body = @{ data = $yaml } | ConvertTo-Json -Compress -Depth 5
  $hp = @{ Authorization="Bearer $tok"; 'Content-Type'='application/json'; 'If-Match'='*' }
  Invoke-RestMethod -Uri "$env_/api/data/v9.2/botcomponents($gptId)" -Method Patch -Headers $hp -Body $body
  $r = Invoke-RestMethod -Uri "$env_/api/data/v9.2/botcomponents($gptId)?`$select=data,modifiedon" -Headers $h
  "patched bytes=$($r.data.Length) modified=$($r.modifiedon)"
}

function Publish-Bot { pac copilot publish --bot $botId }
```

### 13.3. Last call summary (`msdyn_ocliveworkitem`)

```pwsh
$sel = 'msdyn_title,msdyn_transfercount,msdyn_escalationcount,_msdyn_activeagentid_value,_msdyn_cdsqueueid_value,msdyn_statuschangereason,statecode,createdon,modifiedon'
(Invoke-RestMethod -Uri "$env_/api/data/v9.2/msdyn_ocliveworkitems?`$select=$sel&`$orderby=modifiedon desc&`$top=1" -Headers $hFmt).value |
  Format-List msdyn_title, msdyn_transfercount, msdyn_escalationcount, '_msdyn_activeagentid_value@OData.Community.Display.V1.FormattedValue', msdyn_statuschangereason, modifiedon
```

### 13.4. Newest transcript with substantive content

```pwsh
$top = (Invoke-RestMethod -Uri "$env_/api/data/v9.2/conversationtranscripts?`$top=1&`$orderby=createdon desc&`$select=conversationtranscriptid,createdon" -Headers $h).value[0]
$r = Invoke-RestMethod -Uri "$env_/api/data/v9.2/conversationtranscripts($($top.conversationtranscriptid))?`$select=content" -Headers $h
"id=$($top.conversationtranscriptid) created=$($top.createdon) bytes=$($r.content.Length)"
$r.content | Out-File "$env:TEMP\transcript-latest.json" -Encoding utf8 -NoNewline
```

### 13.5. Timeline dump (the workhorse)

```pwsh
$j = Get-Content "$env:TEMP\transcript-latest.json" -Raw | ConvertFrom-Json
"Activities: $($j.activities.Count)"
$j.activities | ForEach-Object {
  $t = if ($_.timestampMs) { (Get-Date '1970-01-01').AddMilliseconds($_.timestampMs).ToLocalTime().ToString('HH:mm:ss.f') } else { '--' }
  if ($_.type -eq 'message') {
    $text = $_.text -replace "`r"," " -replace "`n"," "
    if ($text.Length -gt 300) { $text = $text.Substring(0,300)+'...' }
    $who = if ($_.from.role -eq 0) { 'BOT ' } else { 'USER' }
    "[$t] $who $text"
  } elseif ($_.type -eq 'event') {
    $val = ''
    if ($_.value -and $_.value.ask)         { $val = "ask='$($_.value.ask)'" }
    elseif ($_.value -and $_.value.taskDialogId) { $val = $_.value.taskDialogId }
    "[$t] EVT/$($_.name) $val"
  }
}
```

### 13.6. Find the case for the call

```pwsh
$since = (Get-Date).AddMinutes(-15).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
(Invoke-RestMethod -Uri "$env_/api/data/v9.2/incidents?`$select=ticketnumber,title,description,createdon,_subjectid_value&`$filter=createdon ge $since&`$orderby=createdon desc&`$top=5" -Headers $hFmt).value |
  Format-Table createdon, ticketnumber, title, '_subjectid_value@OData.Community.Display.V1.FormattedValue' -AutoSize
```

### 13.7. Fetch the F6 conversation-note for a case

```pwsh
$caseId = '<incidentid>'
(Invoke-RestMethod -Uri "$env_/api/data/v9.2/annotations?`$filter=_objectid_value eq $caseId&`$select=subject,notetext,createdon" -Headers $h).value |
  ForEach-Object { "--- $($_.createdon) — $($_.subject) ---"; $_.notetext }
```

---

## 14. Troubleshooting checklist

Run through this list when "something is wrong" but you don't know where to start.

- [ ] Is `pac auth list` showing the right profile as Active?
- [ ] Does `az account show` return the right tenant/user?
- [ ] Does WhoAmI on the Dataverse env succeed?
- [ ] Is your local YAML the same as the live one? (Pull and diff.)
- [ ] Is the version marker in the live YAML what you expect?
- [ ] Did `pac copilot publish` finish with "Published successfully!"?
- [ ] On the test call, is there a `conversationtranscript` row with substantive (>5KB) content?
- [ ] Does the transcript show `DynamicPlanReceived` for the user turn you expected?
- [ ] Does the transcript show the expected `DynamicPlanStepTriggered` (right tool/topic)?
- [ ] Does `DynamicPlanStepFinished` appear? How long did the tool take?
- [ ] What is `msdyn_ocliveworkitem.msdyn_transfercount` / `msdyn_escalationcount`?
- [ ] Did the expected case actually appear in `incidents`? Is its title/description/subject correct?
- [ ] Did the F6 note appear? Does it match the conversation?
- [ ] Are there any silent gaps >3s in the timeline?
- [ ] Did the bot drift from any mandated EXACT phrasing?

If all boxes are checked and the behaviour is still wrong, increment your version marker, add a more aggressive rule for the specific failure, and run the loop again.

---

## 15. Further reading

- Companion skill: `skills/power-platform/copilot-studio-voice-agent/SKILL.md` — original escalation-focused runbook.
- Companion skill: `skills/power-platform/knowledge-base-article/SKILL.md` — KB article lifecycle (the bot's F3 KB lookup target).
- User memory: `copilot-studio-voice-escalation.md` — the canonical escalation fix.
- User memory: `dataverse-subject-featuremask.md` — the subjects/featuremask trap.
- Microsoft Learn: search for *"Copilot Studio realtime voice"*, *"botcomponent table"*, *"Dataverse Web API patch"* via the `microsoft_docs_search` tool.

---

## Appendix A — credits and provenance

This skill was distilled from the iterative tuning work on the a realtime voice agent agent in a Dynamics 365 Contact Center test environment (May 2026), versions v3 through v10. Every pattern in §11 is from a real bug observed on a real test call, with the fix verified by a follow-up call and forensic transcript review. The seven-step loop in §7 is what those iterations actually looked like in practice.

If you adopt this skill for a different agent, the only things that change are the three magic IDs in §6 and the brand-specific phrasing in §11.4 and §11.8. Everything else is generic to Copilot Studio Realtime Voice.
