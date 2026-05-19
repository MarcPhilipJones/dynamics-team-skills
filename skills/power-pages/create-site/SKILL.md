---
name: power-pages-create-site
description: >
  Use when the user asks to "create a Power Pages site", "build a code site",
  "scaffold a website", "create a portal", or "make a new site". Creates a
  Power Pages Code Site (SPA) using React, Angular, Vue, or Astro.
version: 1.0.0
author: Marc
applyTo: "powerpages.config.json,**/powerpages.config.json"
tags:
  - power-pages
  - code-site
  - scaffold
  - react
  - vue
  - angular
  - astro
---

# Create a Power Pages Code Site

> **Trigger**: "Create a Power Pages site with React for [purpose]"

Create a complete, production-quality Power Pages Code Site from initial concept
to deployment-ready state. Code Sites use the **v2 data model** and are stored as
`powerpagesite` records (NOT `adx_website`).

## Prerequisites

- **Node.js LTS** installed
- **PAC CLI** installed: `dotnet tool install -g Microsoft.PowerApps.CLI.Tool`
- **Azure CLI** installed (for Dataverse token acquisition)

## Before You Start

1. Use the **Dataverse MCP** to query the target environment and verify no
   existing site conflicts:
   ```
   pac paportal list
   ```
2. Use the **Microsoft Learn MCP** to confirm the latest supported frameworks
   for Code Sites (React, Vue, Angular, Astro -- NOT Next.js, Nuxt, Remix, SvelteKit).

## Step-by-Step Procedure

### Phase 1: Discovery

1. Clarify site purpose, name, audience (internal vs external), and framework choice.
2. Derive naming values:
   - `SITE_NAME` -- Title Case (e.g., "Contoso Portal")
   - `SITE_SLUG` -- kebab-case (e.g., "contoso-portal")
   - `SITE_DESCRIPTION` -- one-line summary
3. Determine project location (current directory, new subfolder, or custom path).
4. Confirm all choices with the user before proceeding.

### Phase 2: Scaffold & Launch Dev Server

1. Initialize the project with the chosen framework CLI:
   - **React**: `npm create vite@latest <SITE_SLUG> -- --template react-ts`
   - **Vue**: `npm create vite@latest <SITE_SLUG> -- --template vue-ts`
   - **Angular**: `ng new <SITE_SLUG> --routing --style=css`
   - **Astro**: `npm create astro@latest <SITE_SLUG>`
2. Create `powerpages.config.json` in the project root:
   ```json
   {
     "siteName": "<SITE_NAME>",
     "siteSlug": "<SITE_SLUG>",
     "framework": "<react|vue|angular|astro>"
   }
   ```
3. Run `npm install`.
4. Initialize git: `git init && git add -A && git commit -m "Initial scaffold: <SITE_NAME>"`.
5. Start the dev server: `npm run dev` (background).
6. Share the dev server URL with the user.

### Phase 3: Component & Design Planning

1. Determine pages, components, and routes needed.
2. Choose design direction: typography (Google Fonts), color palette (CSS custom
   properties), motion/animation plan.
3. Present the component plan as a table for user review.

### Phase 4: Plan Approval

Present the full implementation plan covering:
- Pages with content outlines
- Design decisions (fonts, colors, motion)
- Routing and navigation structure

Get explicit user approval before building.

### Phase 5: Implementation

1. Create design foundations -- `theme.css` with CSS custom properties.
2. Build layout (header, footer, navigation).
3. Build shared components.
4. Build each page with real content and styling.
5. Configure router with all routes.
6. Use real images from Unsplash (not placeholders).
7. **Commit after every page/component** -- individual commits for easy rollback.

### Phase 6: Review

1. Verify all pages render correctly.
2. Present a summary table of what was built.
3. Share the dev server URL and ask user to review.
4. Apply any requested changes.

### Phase 7: Deployment

1. Ask user if they want to deploy now.
2. If yes, follow the **power-pages/deploy** skill.
3. Suggest next steps: `/setup-datamodel`, `/setup-auth`, `/add-sample-data`.
4. **If the site is on a trial / developer environment and needs to be Public**: remind the user that maker portal's **Public** toggle is blocked by default tenant governance, and the fix is a tenant-admin toggle in https://admin.powerplatform.microsoft.com/ → **Manage** → **Power Pages** → **Governance controls** → **"Set site visibility to public access for non-production sites"** → environment → **None → All** → **Save**. **Do NOT suggest converting the trial to production** — that path will fail for code sites / SPAs. Reference: https://learn.microsoft.com/power-pages/admin/site-visibility-governance

## PAC CLI Commands Used

```powershell
# List existing sites
pac paportal list

# Deploy the site (after build)
pac pages upload-code-site --rootPath "<PROJECT_ROOT>"
```

## Common Mistakes & Warnings

- **Only static SPA frameworks are supported** -- Next.js, Nuxt.js, Remix,
  SvelteKit, and Liquid are NOT supported for Code Sites.
- **Code Sites use v2 data model** -- stored as `powerpagesite` records, NOT
  `adx_website`. Do NOT use `pac paportal upload/download`.
- **Always use `pac pages upload-code-site`** -- never `pac paportal upload`.
- **The `powerpages.config.json` file is required** -- PAC CLI uses it to
  identify the project.
- **Do not use generic fonts** -- apply distinctive typography via Google Fonts.
- **Build before deploying** -- always run `npm run build` first.
- **JavaScript attachment blocking** -- some environments block `.js` uploads.
  Check and unblock via `pac env list-settings` / `pac env update-settings`.
