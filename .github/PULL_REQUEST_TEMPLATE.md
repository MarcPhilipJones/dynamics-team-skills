# PR — <Skill name or change>

## Summary

<!-- One paragraph: what this PR adds or changes, and why. -->

## Type of change

- [ ] New skill
- [ ] Update to existing skill
- [ ] Documentation / README / CONTRIBUTING change
- [ ] Tooling / scripts
- [ ] Other (describe)

## Skill checklist (if applicable)

- [ ] Folder name is kebab-case
- [ ] `SKILL.md` has valid YAML front-matter
- [ ] `name:` field matches the folder leaf name
- [ ] `description:` field includes natural trigger phrases ("use when…")
- [ ] `version:` follows semver
- [ ] Skill is in the appropriate category folder
- [ ] [`skills/INDEX.md`](../skills/INDEX.md) entry added or updated

## Sanitisation checklist (every PR)

- [ ] No tenant org URLs (use `https://<your-org>.crm.dynamics.com`)
- [ ] No Bot / Copilot / environment IDs (use `<your-bot-id>` etc.)
- [ ] No real customer names (use `ProjectA`, `ProjectB`, or industry archetypes)
- [ ] No API keys, SAS URLs, secrets, PATs, certificates, private keys
- [ ] No admin emails (use `admin@<your-tenant>.onmicrosoft.com` if needed)
- [ ] No internal resource group names (use `rg-<project>`)

## Compatibility

- [ ] All paths use forward slashes or are PowerShell-quoted appropriately
- [ ] PowerShell snippets work in `pwsh` 7+ (avoid Windows-PowerShell-only constructs unless flagged)
- [ ] No hard-coded Windows paths in the skill content itself

## Notes for reviewers

<!-- Anything reviewer should know: which file to focus on, a tricky claim
that needs sanity-checking, a version bump that may surprise. -->

## Disclaimer

- [ ] The verbatim disclaimer at the top of [`README.md`](../README.md) is unchanged
