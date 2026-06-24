---
name: power-platform-skills-index
description: >
  Index of all Power Platform and Power Pages skills. Use this to find the right
  skill for any Power Platform task.
version: 1.0.0
author: Marc
---

# Power Platform Skills Index

## Power Pages Skills

| Skill | Trigger Phrases | Description |
|---|---|---|
| [create-site](power-pages/create-site/SKILL.md) | "create a site", "scaffold a website", "build a portal" | Scaffold a Power Pages Code Site (React/Vue/Angular/Astro) |
| [setup-datamodel](power-pages/setup-datamodel/SKILL.md) | "create tables", "design the database", "set up data model" | Create Dataverse tables, columns, and relationships via OData API |
| [setup-webapi](power-pages/setup-webapi/SKILL.md) | "connect to API", "wire up data", "set up Web API" | Generate TypeScript services, types, and hooks for /_api/ endpoints |
| [setup-permissions](power-pages/setup-permissions/SKILL.md) | "set up permissions", "fix 403", "enable Web API" | Create site settings + table permissions via OData API |
| [setup-auth](power-pages/setup-auth/SKILL.md) | "add login", "set up authentication", "configure Entra ID" | Entra ID login/logout, auth context, protected routes |
| [fix-profile-redirect](power-pages/fix-profile-redirect/SKILL.md) | "redirected to profile after login", "profile page after sign-in", "fix profile redirect" | Fix /profile redirect after sign-in: YAML fix + JS defense + debug logging |
| [setup-webroles](power-pages/setup-webroles/SKILL.md) | "create web roles", "set up roles" | Create anonymous, authenticated, and custom web roles |
| [add-sample-data](power-pages/add-sample-data/SKILL.md) | "add sample data", "seed the database", "populate tables" | Insert realistic sample records via OData API |
| [deploy](power-pages/deploy/SKILL.md) | "deploy the site", "first deploy", "go live" | First-time deployment via pac pages upload-code-site |
| [upload](power-pages/upload/SKILL.md) | "redeploy", "push changes", "upload changes", "safe update and restart" | Safe update: build, upload, restart with pre-flight checks and portal ID lookup |
| [restart-site](power-pages/restart-site/SKILL.md) | "restart the site", "restart Power Pages", "clear site cache" | Restart site via Power Platform Admin REST API |
| [code-sites-v2-reference](power-pages/code-sites-v2-reference/SKILL.md) | "code sites vs portals", "component types", "YAML overwrite" | Reference: v2 data model, component types, YAML behaviour |
| [omnichannel-custom-chat-widget](power-pages/omnichannel-custom-chat-widget/SKILL.md) | "add live chat", "chat widget", "agent sees visitor", "chat not authenticating" | Custom React chat widget with omnichannel-chat-sdk, authenticated chat, Vite setup |
| [case-listing](power-pages/case-listing/SKILL.md) | "cases page is blank", "case list not loading", "add cases page", "fix support cases" | Case listing & detail pages: auth, contact filter, null guards, debug logging |
| [spa-page-scaffold](power-pages/spa-page-scaffold/SKILL.md) | "add a new page", "create a page for X", "scaffold a page" | Robust page template with auth, null-safety, debug logging, error states |
| [embedding-advanced-widget](power-pages/embedding-advanced-widget/SKILL.md) | "embed widget", "add chat bubble", "third-party script", "CSP error on widget" | Embed third-party JS widgets without CSP violations: self-host scripts, React wrapper, Liquid injection |
| [profile-picture-upload](power-pages/profile-picture-upload/SKILL.md) | "add profile picture", "avatar upload", "two photos on profile", "duplicate profile image" | Profile picture upload via built-in Profile/ShowImage + Bootstrap modal CSS fix |
| [web-api-odata-bind-security](power-pages/web-api-odata-bind-security/SKILL.md) | "permission to associate", "odata.bind 403", "appendto missing", "pricelevel permission" | Complete guide to @odata.bind security: Web API settings + table permissions + checklist |

## Cross-Cutting Skills

| Skill | Trigger Phrases | Description |
|---|---|---|
| [web-accessibility](web-accessibility/SKILL.md) | "check accessibility", "WCAG audit", "fix contrast", "add ARIA", "keyboard navigation", "make accessible" | WCAG 2.1 AA: semantic HTML, keyboard nav, ARIA, focus management, contrast, testing |

## Power Platform Skills

| Skill | Trigger Phrases | Description |
|---|---|---|
| [add-html-tab](power-platform/add-html-tab/SKILL.md) | "add a tab to a form", "embed an HTML page on a form", "add a web resource tab", "do it like the Usage tab" | Add a model-driven form tab hosting a single-page HTML web resource (live-bound to the record), with backup, publish, verify, and rollback |
| [solution-packager](power-platform/solution-packager/SKILL.md) | "export solution", "import solution", "manage ALM" | Full solution lifecycle: export, unpack, pack, import |
| [fetchxml-builder](power-platform/fetchxml-builder/SKILL.md) | "build FetchXML", "query Dataverse", "filter records" | Construct FetchXML queries with filters, joins, aggregation |
| [knowledge-base-article](power-platform/knowledge-base-article/SKILL.md) | "create KB articles", "set up knowledge base" | knowledgearticle CRUD, lifecycle states, Web API + frontend integration |
| [case-notes-and-attachments](power-platform/case-notes-and-attachments/SKILL.md) | "add notes to cases", "attach files", "fix annotation errors" | Annotation CRUD with @odata.bind linking, file attachments, troubleshooting |
| [knowledge-base-public-links-for-spa](power-platform/knowledge-base-public-links-for-spa/SKILL.md) | "fix KB links", "article detail page", "knowledge base blank screen" | SPA detail route + component for public-facing KB article URLs |
| [copilot-studio-voice-agent](power-platform/copilot-studio-voice-agent/SKILL.md) | "voice agent debug", "escalation doesn't fire", "GPT silent on handoff", "realtime voice agent" | Runbook for Copilot Studio Realtime Voice agents — escalation, topic vs GPT decomposition, Dataverse MCP edit loop |
| [copilot-voice-agent-forensics](power-platform/copilot-voice-agent-forensics/SKILL.md) | "voice agent forensics", "conversationtranscript analysis", "voice latency", "why did the bot say that" | End-to-end runbook: headless authoring, runtime forensics (LWI/sessions/queue), transcript analysis, 7-step iteration loop |

## Dataverse Skills

| Skill | Trigger Phrases | Description |
|---|---|---|
| [change-record-owner](dataverse/change-record-owner/SKILL.md) | "change owner", "assign to team", "set ownership via Logic App" | Change record owner to a team via Logic App Dataverse connector or direct Web API |

## General / Productivity Skills

| Skill | Trigger Phrases | Description |
|---|---|---|
| [markdown-to-pdf](general/markdown-to-pdf/SKILL.md) | "generate PDF", "convert to PDF", "create branded handout", "export PDF" | Markdown → styled PDF with pre-rendered Mermaid diagrams, CSS branding, A4 formatting |
| [elite-powerpoint](general/elite-powerpoint/SKILL.md) | "build a PowerPoint", "create a deck", "presentation", "slides", "pitch deck", "restyle the pptx", "Fluent 2 deck", "D365 template" | Editable, professional decks via python-pptx + D365 template + Fluent 2 design tokens, with mandatory visual self-check loop |
| [elite-powerpoint-designer](general/elite-powerpoint-designer/SKILL.md) | "design a deck", "brand style", "slide design philosophy", "animation guidelines", "presentation style" | Generic design-philosophy framework: brand styles, template mapping, animation/transition guidelines, polish heuristics |
| [image-selection-guidance](general/image-selection-guidance/SKILL.md) | "pick an image", "find a photo", "hero image", "stock image", "slide visual" | Curate stock images for slides: Unsplash vs Pexels decision logic, intelligent search, quality standards |
| [project-manager-add-workspace](general/project-manager-add-workspace/SKILL.md) | "add workspace to project manager", "register this workspace", "save workspace in project manager" | Add current VS Code workspace to Project Manager saved projects with duplicate protection and no mutation of existing entries |
| [figma-design-extraction](general/figma-design-extraction/SKILL.md) | "extract the Figma", "rebuild this design", "Figma to code", "Figma MCP", "get the design tokens", "Dev Mode MCP not showing" | Extract a Figma design (tokens, assets, layout) via Dev Mode MCP or the REST fallback and rebuild it as a coded SPA for a demo |
| [brand-central](general/brand-central/SKILL.md) | "find a Microsoft logo", "Brand Central", "product icon", "official Microsoft asset", "Copilot icon", "M365 icon", "Dynamics icon", "Azure icon", "branded hero image" | Navigate brandcentral.microsoft.com to source on-brand Microsoft visuals: asset selection by surface, format decision (SVG/PNG/EPS), usage rights, integration into decks / Power Pages / Code Apps |

## PowerPoint Skills

| Skill | Trigger Phrases | Description |
|---|---|---|
| [marcs-powerpoint-creator-fluent](powerpoint/marcs-powerpoint-creator-fluent/SKILL.md) | "Marc's PowerPoint Creator", "Fluent 2 deck two-phase", "build a Microsoft Dynamics 365 deck" | Two-phase Fluent 2 / D365 deck builder: Phase 1 headless python-pptx with ≥3 self-iterations + validation report; Phase 2 PptMcp thumbnails + 4-column review table + targeted COM refinement on Marc-nominated slides only |

## Code Apps Skills

| Skill | Trigger Phrases | Description |
|---|---|---|
| [code-apps-reference](code-apps/code-apps-reference/SKILL.md) | "build a code app", "power apps code app", "power-apps init", "pac code deprecated", "add dataverse to code app", "fluent ui v9" | Comprehensive guide (GA, new `power-apps` npm CLI): scaffolding, Dataverse + connectors, OData/FetchXML, CRUD, bulk ops, security, Fluent UI v9, ALM, known issues, troubleshooting |

## Azure Skills

| Skill | Trigger Phrases | Description |
|---|---|---|
| [conditional-access-arm-mfa](azure/conditional-access-arm-mfa/SKILL.md) | "AADSTS50158", "AADSTS50076", "az login MFA", "device code MFA fails", "ARM vs Kudu auth" | When and why ARM writes need MFA-capable auth while Kudu/SCM ZIP deploys don't — with auth-method decision matrix |

## Typical Workflow Order

For a new Power Pages project, follow this sequence:

1. **create-site** -- Scaffold the project
2. **deploy** -- First deployment (creates the site record)
3. **setup-datamodel** -- Create Dataverse tables
4. **setup-permissions** -- Enable Web API + table permissions
5. **add-sample-data** -- Populate tables with test data
6. **setup-webapi** -- Generate TypeScript services
7. **setup-auth** -- Add Entra ID authentication
8. **setup-webroles** -- Configure role-based access
9. **upload** -- Redeploy with all changes
10. **restart-site** -- Restart if auth/security/settings changed

> **Reference**: Consult **code-sites-v2-reference** at any time for v2 data
> model details, component type codes, and YAML deployment behaviour.

## Key References

- **Code Sites v2 Data Model**: Sites are `powerpagesite` records (NOT `adx_website`)
- **PAC CLI for Code Sites**: Use `pac pages upload-code-site` (NOT `pac paportal upload`)
- **Site Settings**: `powerpagecomponent` type 9 (CAN be created via API)
- **Table Permissions**: `powerpagecomponent` type 18 (CAN be created via OData API; restart site after)
- **Token Acquisition**: `az account get-access-token --resource $envUrl`
