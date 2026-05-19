# Dynamics Team Skills

> *Personal collection of GitHub Copilot skills for Dynamics 365 / Power Platform
> work. Not officially supported. Provided as-is, may be stale, no warranties,
> not endorsed by Microsoft. Intended for colleagues and partners who have been
> given the link directly.*

A curated set of [GitHub Copilot skills](https://docs.github.com/en/copilot/concepts/about-customizing-github-copilot-chat-responses)
covering Power Pages, Power Platform, Dataverse, Code Apps, Copilot Studio,
Azure, and presentation tooling.

This repo is **public but unadvertised** — share the URL with colleagues or
partners directly. Do not link it from official channels.

---

## What's in here

34 SKILL.md files across 8 categories. See the full index at
[`skills/INDEX.md`](skills/INDEX.md).

| Category | Count | Focus |
|---|---|---|
| [`skills/power-pages/`](skills/power-pages/) | 18 | Power Pages code sites: scaffolding, deploy, auth, Web API, table permissions, omnichannel chat widget, KB integration, page scaffolds |
| [`skills/power-platform/`](skills/power-platform/) | 7 | Solution ALM, FetchXML, KB articles, annotations, Copilot Studio voice agents, voice-agent forensics |
| [`skills/general/`](skills/general/) | 4 | PowerPoint generation, image curation, markdown→PDF |
| [`skills/dataverse/`](skills/dataverse/) | 1 | Record ownership via Logic App / Web API |
| [`skills/code-apps/`](skills/code-apps/) | 1 | Power Apps Code Apps reference (Dataverse + Fluent UI v9) |
| [`skills/azure/`](skills/azure/) | 1 | Azure CLI auth under Conditional Access (ARM vs Kudu/SCM, MFA) |
| [`skills/powerpoint/`](skills/powerpoint/) | 1 | Two-phase Fluent 2 / D365 deck builder |
| [`skills/web-accessibility/`](skills/web-accessibility/) | 1 | WCAG 2.1 AA: semantic HTML, ARIA, keyboard, contrast |

Every skill is a folder with a `SKILL.md` front-matter file. The front-matter
`description` field contains the trigger phrases that should invoke the skill.

---

## Installation

### Option 1 — Clone and reference manually

```powershell
git clone https://github.com/MarcPhilipJones/dynamics-team-skills.git ~/.agents/dynamics-team-skills
```

Open any `skills/<category>/<skill-name>/SKILL.md` and copy the content (or its
trigger phrases) into your Copilot chat when you need it.

### Option 2 — Browse on GitHub

The repo is fully browseable on github.com. Search the [`skills/INDEX.md`](skills/INDEX.md)
trigger-phrase table for the task you have at hand.

### Option 3 — Future: VS Code plugin

A [`github/awesome-copilot`](https://github.com/github/awesome-copilot)-style
plugin that surfaces these skills inline in Copilot Chat is planned. Watch
this README for installation instructions when it lands.

---

## Conventions

- All folder and file names are **kebab-case** (Linux-safe, GitHub-runner-safe)
- Every skill has YAML front-matter: `name`, `description`, `version`, `author`, optional `applyTo`, `tags`
- The `name` field matches the folder leaf (e.g. folder `case-listing/` ⇒ `name: case-listing`)
- No tenant GUIDs, no customer names, no API keys, no SAS URLs — all sanitised to placeholders like `<your-org>.crm.dynamics.com`, `<your-copilot-id>`, `<your-bot-id>`

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the full author checklist.

---

## Contributing

Open a PR. The [`CONTRIBUTING.md`](CONTRIBUTING.md) covers:

- The naming rules above
- How to add a new skill from a `skills/_template/` boilerplate (TBD)
- The "no tenant values, no secrets" sanitisation checklist
- The weekly harvest ritual

PRs require **1 review** before merge.

---

## Caveats

- **Not Microsoft-endorsed.** This is a personal collection. Microsoft has no
  obligation to keep these patterns working as the platform evolves.
- **No warranties.** Patterns are written from real engagements but may go
  stale as APIs, SDKs and platform behaviours change.
- **No customer data.** Skills are sanitised before commit. If you find a
  leaked tenant value or customer name, open an issue (or a PR with the fix)
  immediately.
- **Not for everyone.** The audience is technical Power Platform / D365
  practitioners. If you're new to the platform, Microsoft Learn is the better
  starting point.

---

## Provenance

Curated by [Marc Philip Jones](https://github.com/MarcPhilipJones). Distilled
from real engagements (presales, customer demos, internal tooling, voice agent
tuning). Sanitised for public sharing under MIT.

Skills authored or contributed to by Marc unless otherwise stated in the
front-matter `author` field.
