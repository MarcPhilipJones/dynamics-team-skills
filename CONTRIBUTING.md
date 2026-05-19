# Contributing

Thank you for adding to this collection. The rules below keep the repo
GitHub-safe, share-safe, and easy to navigate.

## The non-negotiables

1. **No tenant values.** Replace all of these with placeholders before commit:
   - Tenant org URLs → `https://<your-org>.crm.dynamics.com`
   - Bot IDs / Copilot IDs → `<your-bot-id>` / `<your-copilot-id>`
   - Schema names → `<your_agent_schemaname>`
   - Resource group names → `rg-<project>`
   - Logic App names → `la-<project>-...`
   - Account emails → omit, or use `admin@<your-tenant>.onmicrosoft.com`
2. **No secrets.** No API keys, SAS URLs, client secrets, certificates,
   private keys, PATs, or anything else that should not be in a public repo.
3. **No customer names.** Use anonymised project labels (e.g. `ProjectA`,
   `ProjectB`) or industry archetypes (e.g. "automotive OEM customer deck",
   "utilities field-service scenario").
4. **kebab-case folder names.** Linux runners are case-sensitive; Windows is
   not. Stick to lowercase kebab-case for every folder and file.
5. **Front-matter is required.** Every `SKILL.md` starts with YAML front-matter:
   ```yaml
   ---
   name: <leaf-kebab-case>
   description: >
     What it does. Trigger phrases the user might say. Use when X, fix Y.
   version: 1.0.0
   author: <Your name>
   applyTo: "<optional glob>"
   tags:
     - <list>
   ---
   ```
6. **The `name` field matches the folder leaf.** Folder `case-listing/` →
   `name: case-listing`. No prefixes like `power-pages-case-listing`.

## Adding a new skill

1. Create the folder: `skills/<category>/<skill-name>/SKILL.md`.
   - Pick an existing category if one fits.
   - If you need a new category, propose it in the PR description — keep them
     stable; we don't want 30 single-skill categories.
2. Write the SKILL.md with valid front-matter.
3. Strip tenant values, secrets, customer names (see non-negotiables above).
4. Add a row to [`skills/INDEX.md`](skills/INDEX.md) in the right category.
5. Open a PR.

## Updating an existing skill

1. Find it: `skills/<category>/<skill-name>/SKILL.md`.
2. Bump the `version:` in the front-matter (semver: patch / minor / major).
3. Add a one-line summary of the change at the top of the body, e.g.:
   > **v1.1.0 — Added Phase 3b: content-store sync (March 2026)**
4. Open a PR.

## Naming

- Skill folder name: kebab-case, descriptive, ≤ 40 characters.
- Skill `name:` field: same as folder name.
- Skill `description:` field: includes trigger phrases ("use when…", "fix Y").
- Skill `tags:` field: lowercase, hyphen-separated, ≤ 6 tags.

## Categories

| Folder | Use for |
|---|---|
| `power-pages/` | Power Pages code sites — scaffolding, deploy, auth, Web API, table permissions, page-level patterns |
| `power-platform/` | Solution ALM, FetchXML, KB articles, Copilot Studio, voice agents |
| `dataverse/` | Direct Dataverse operations: record ownership, FetchXML, plug-ins, security roles |
| `code-apps/` | Power Apps Code Apps (the React/TypeScript flavour) |
| `azure/` | Azure CLI, Azure resources, identity, networking |
| `general/` | Cross-cutting productivity: PowerPoint, PDF, image curation |
| `powerpoint/` | PowerPoint-specific deep skills |
| `web-accessibility/` | Cross-cutting accessibility patterns |

If your skill doesn't fit, propose a new category in the PR.

## The harvest ritual

The repo is curated **weekly** by Marc and two collaborators, ~30 min per
reviewer. The cadence:

1. Each reviewer collects 1–3 skill-worthy patterns from their week's work.
2. Sanitise (no tenant values / secrets / customer names).
3. Open a PR per skill.
4. One reviewer approves; merge.

Don't let perfect be the enemy of good — a sanitised, slightly-rough skill is
more valuable than a polished one that never gets shared.

## Branching & PR workflow

`main` is protected — all changes go through a pull request. Use a short-lived
branch per skill so reviews stay scoped and the history stays readable.

### Branch naming

| Prefix | Use for | Example |
|---|---|---|
| `harvest/` | A brand-new skill being added | `harvest/case-routing-rules` |
| `update/` | Editing an existing skill (bug fix, version bump, clarification) | `update/setup-webapi-v1.2` |
| `chore/` | Repo plumbing: gitignore, README, CONTRIBUTING, INDEX-only changes | `chore/fix-index-typo` |
| `docs/` | Pure documentation changes outside `skills/` | `docs/readme-disclaimer` |

Branch leaf names are kebab-case and match the skill folder where applicable.

### Full flow for a new skill

```pwsh
# 1. Start clean from main
git checkout main
git pull --ff-only origin main

# 2. Create the harvest branch
git checkout -b harvest/<skill-name>

# 3. Add files under skills/<category>/<skill-name>/SKILL.md
#    Update skills/INDEX.md

# 4. Pre-commit safety
#    Run BOTH workspace tasks before pushing:
#    - "Scan for tenant leaks (should print nothing)"   → must be empty
#    - "Count skills by category"                       → sanity check the +1

# 5. Commit & push
git add skills/<category>/<skill-name>/ skills/INDEX.md
git commit -m "harvest: add <skill-name> skill"
git push -u origin harvest/<skill-name>

# 6. Open the PR
gh pr create --fill --base main
```

### Commit message convention

Match the branch prefix to the commit verb:

- `harvest: add <skill-name> skill`
- `update: <skill-name> v1.2.0 — <one-line reason>`
- `chore: <what>`
- `docs: <what>`

### Bypass policy

Marc has bypass permission on the `main` protection rule. Use it only for:

- `.gitignore` / repo plumbing that cannot block a harvest in flight
- Emergency tenant-leak redaction (sanitise immediately, no review delay)

Everything else — including all `harvest/` and `update/` changes — goes
through a PR, even when you're the only reviewer. The audit trail matters.

## PR checklist

The PR template enforces these — see [`.github/PULL_REQUEST_TEMPLATE.md`](.github/PULL_REQUEST_TEMPLATE.md):

- [ ] No tenant values, no secrets, no customer names
- [ ] Front-matter present and well-formed
- [ ] Folder + `name` field both kebab-case
- [ ] Index entry added or updated in `skills/INDEX.md`
- [ ] Tested locally (skill was actually useful for a real task)
- [ ] Disclaimer in `README.md` unchanged

## Code of conduct

Be kind, be technical, be specific. Skills are for engineers in a hurry —
clarity beats cleverness.

## License

By contributing, you agree your contribution is licensed under MIT (see
[`LICENSE`](LICENSE)).
