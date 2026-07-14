---
name: power-platform-ai-builder-prompt-in-flow
description: >
  Use when the user wants to "score with AI instead of a formula", "replace Power Fx
  scoring with an AI prompt", "run an AI Builder prompt in a flow", "use GPT to
  qualify/summarise inside Power Automate", or return structured JSON from a prompt in
  an agent flow. Covers wiring an AI Builder custom prompt into a Dataverse/agent flow
  and parsing its output reliably.
version: 1.0.0
author: Jamie Barker
tags:
  - power-platform
  - ai-builder
  - power-automate
  - copilot-studio
  - prompts
---

# Run an AI Builder prompt inside a flow (replace deterministic logic with GPT)

> **Trigger**: "score/qualify with an AI prompt instead of a Power Fx formula"

Swap brittle rule/keyword logic (e.g. a Power Fx `If(... in Lower(x) ...)` score) for an
**AI Builder custom prompt** that reasons over the text and returns structured JSON. Proven
replacing a lead-qualification scorer in a live SE voice batch flow.

## Prerequisites
- **AI Builder credits/capacity** enabled in the environment (separate from Copilot/voice licensing).
- The flow already has the inputs to score (e.g. the answers) available.

## Step-by-Step Procedure

### 1. Author the prompt (portal — the one manual bit)
- AI Builder → **Prompts** (or Copilot Studio → add a prompt). Define text inputs, and
  instruct it to **return ONLY strict JSON**, e.g.
  `{"score": <0-100>, "band": "Sales-Ready|Nurture|Disqualify", "rationale": "<one sentence>"}`.
- Keep bands aligned to your routing thresholds so downstream flows don't change.

### 2. Add the "Run a prompt" action in the flow designer
- Add **Run a prompt**, pick the prompt, map the inputs. It authorises via the AI Builder
  connection (in practice it **reuses the Dataverse connection** — no new connector needed).
- The action's host is `operationId: aibuilderpredict_customprompt`,
  `apiId: providers/Microsoft.ProcessSimple/operationGroups/aibuilder`. Inputs land under
  `item/requestv2/<inputName>`.

### 3. Parse the output (do this via API or designer)
- The generated text is at
  `@body('Run_a_prompt')?['responsev2']?['predictionOutput']?['text']`.
- Add a **Compose** that strips markdown fences and coalesces likely paths, then `json()` it:
  ```
  Compose_ScoreText = @trim(replace(replace(coalesce(
    body('Run_a_prompt')?['responsev2']?['predictionOutput']?['text'],
    body('Run_a_prompt')?['predictionOutput']?['text'],
    body('Run_a_prompt')?['text'], '{}'), '```json',''), '```',''))
  score = @int(coalesce(json(outputs('Compose_ScoreText'))?['score'], 0))
  ```
- Use `score`/`rationale` in your Update/Create actions.

### 4. Retire the old logic
- Remove the Power Fx scoring node from the agent topic and stop passing the old score
  (bind the flow's now-unused score input to `=0`). The flow owns scoring.

## Common Mistakes & Warnings
- **Don't hand-author the AI Builder action via raw API** — its connector identity + connection
  aren't reliably scriptable; add the **Run a prompt** action in the **designer**, then wire the
  Parse/score steps (those are safe to do via `clientdata` PATCH).
- **Always strip code fences** — GPT sometimes wraps JSON in ```` ```json ````; a raw `json()`
  then throws and fails the action.
- **Validate the output path with one real run** — if the score comes back `0`, the
  `responsev2/predictionOutput/text` path differs; read the run history and adjust the coalesce.
- **Keep bands matching your router** — the prompt's band thresholds should mirror the existing
  score-and-route flow so behaviour is unchanged.
- Verified live: reasoned scores (a weak lead scored ~52 → Nurture, a strong senior/enterprise
  lead ~95 → Sales-Ready) vs the old keyword formula's near-identical-but-blind numbers.

## Key Takeaway

> Author the prompt in the portal to return **strict JSON**, add **Run a prompt** in the
> designer (it reuses the Dataverse connection), then Compose+`json()` the text at
> `responsev2/predictionOutput/text` (fence-stripped) to drive your fields — and delete the
> old Power Fx node.
