---
name: power-platform-knowledge-base-public-links-for-spa
description: >
  Use when the user asks to "fix KB links", "add article detail page",
  "knowledge base blank screen", "KB article shows blank", "public article URL",
  or "knowledgebase/article route not working".
  Adds the missing SPA route and detail component so that public-facing
  knowledge article URLs (e.g. /knowledgebase/article/KA-01602/en-us) render
  correctly in a Power Pages Code Site SPA.
version: 1.0.0
author: Marc
tags:
  - power-platform
  - knowledge-base
  - knowledgearticle
  - power-pages
  - spa
  - react-router
---

# Knowledge Base Public Article Links for SPA Code Sites

> **Trigger**: "Fix KB article blank screen" or "Add article detail page"

## Problem

Power Pages Code Site SPAs typically have a Knowledge Base listing page that
generates links like:

```
/knowledgebase/article/KA-01602/en-us
```

This matches the traditional Power Pages KB URL pattern. However, in an SPA
there is **no React Router route** for this path — clicking the link shows a
blank screen.

## Solution Overview

1. Create a `KnowledgeArticleDetail` component that reads `:articleNumber` from
   the URL.
2. Fetch the article from `/_api/knowledgearticles` filtered by
   `articlepublicnumber` and `statecode eq 3` (published).
3. Render the HTML `content` field.
4. Register the route in React Router.

## Prerequisites

- Knowledge articles exist and are **published** (statecode = 3).
- `Webapi/knowledgearticle/enabled` = `true` (site setting).
- `Webapi/knowledgearticle/fields` includes `content` (or use `*`).
- Table permission for `knowledgearticle` with Read access assigned to the
  appropriate web roles.
- The listing page links use the format
  `/knowledgebase/article/{articlepublicnumber}/en-us`.

## Reference Implementation

The canonical working implementation is in **ProjectB** and **ProjectA**:

- **ProjectB Component**: `ProjectB/SSENTPortal/src/pages/KnowledgeArticleDetail.tsx`
- **ProjectA Component**: `ProjectA/src/pages/KBArticleDetail.tsx`
- **Route pattern**: `/knowledgebase/article/:articleNumber/:lang`

Use these as templates when adding the same pattern to new projects.

## Step-by-Step Procedure

### Step 1: Add the React Router Route

In `App.tsx`, import the detail component and add the route alongside the
existing KB listing route:

```tsx
import KnowledgeArticleDetail from './pages/KnowledgeArticleDetail';

// Inside <Routes>:
<Route path="/knowledge" element={<KnowledgeBase />} />
<Route path="/knowledgebase/article/:articleNumber/:lang" element={<KnowledgeArticleDetail />} />
```

The `:lang` parameter is captured for future multi-language support but is
unused in the initial implementation.

### Step 2: Create the Detail Component

Create `src/pages/KnowledgeArticleDetail.tsx`:

Key patterns:
- Extract `articleNumber` via `useParams()`
- Fetch with filter: `articlepublicnumber eq '{number}' and statecode eq 3`
- **Always include `content` in `$select`** — the listing page omits it for
  performance but the detail page needs it
- Handle loading, error, and not-found states
- Render HTML content with `dangerouslySetInnerHTML`
- Include a back-link to `/knowledge`

```tsx
// API call pattern:
apiRequest<ODataResponse<KnowledgeArticle>>(
  `/knowledgearticles?$select=knowledgearticleid,title,description,content,keywords,articlepublicnumber,statecode,createdon,modifiedon&$filter=articlepublicnumber eq '${encodeURIComponent(articleNumber)}' and statecode eq 3&$top=1`
)
```

### Step 3: Style the Content

Create `src/pages/KnowledgeArticleDetail.css`:

Key considerations:
- Dataverse article `content` has **inline styles** (font-family, font-size,
  color) that conflict with the site theme
- Use `!important` overrides on `.ka-content h1, h2, p, li` to enforce the
  site's design tokens
- Wrap content in a `.ka-content-wrapper` card with border, padding, and shadow
- Style the article number badge similar to case ticket number badges

### Step 4: Verify the Fields Site Setting

Ensure `content` is in the `Webapi/knowledgearticle/fields` site setting.
Query via Dataverse MCP:

```sql
SELECT name, content FROM powerpagecomponent
WHERE name LIKE '%knowledgearticle/fields%' AND powerpagecomponenttype = 9
```

If `content` is missing, update the setting or use `*` (wildcard).

## Common Mistakes

- **Using `<a href>` instead of `<Link to>` in the listing page** — This is the
  #1 mistake. External `<a href="#">` or `<a href={externalUrl}>` links will
  NOT navigate within the SPA. **Always use React Router `<Link to>` in the
  listing page** to link to the article detail route. Example:
  ```tsx
  <Link to={`/knowledgebase/article/${article.articlepublicnumber}/en-us`}>
    {article.title ?? '(No title)'}
  </Link>
  ```
- **Using `externalLink` or `msdyn_externalreferenceid` as href** — KB article
  content is stored in the Dataverse `content` field and should be rendered
  inline in the detail page, not linked externally. Don't invent an external
  link field — the content is already there.
- **Forgetting the route** — Register the `/knowledgebase/article/:articleNumber/:lang`
  route in App.tsx. Without it, clicking article links shows a blank page.
- **Missing `content` in fields** — The listing page works without it, so it's
  easy to forget. The detail page will show "No content available" if omitted.
- **Not filtering for published** — Draft articles (statecode 0) are visible
  via the API but shouldn't be shown to portal users. Always filter `statecode eq 3`.
- **URL encoding** — Use `encodeURIComponent(articleNumber)` in the API query
  to handle special characters in article numbers.

## Related Skills

- [knowledge-base-article](../knowledge-base-article/SKILL.md) — Full KB
  lifecycle: create, publish, Web API setup, frontend integration
- [setup-permissions](../../power-pages/setup-permissions/SKILL.md) — Web API
  site settings and table permissions
- [setup-webapi](../../power-pages/setup-webapi/SKILL.md) — Shared API client
  with anti-forgery token support
