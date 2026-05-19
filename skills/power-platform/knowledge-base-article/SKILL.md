---
name: power-platform-knowledge-base-article
description: >
  Use when the user asks to "create knowledge articles", "set up KB",
  "manage knowledge base", "publish articles", or "integrate knowledge articles".
  Handles the knowledgearticle table lifecycle: CRUD, article states, Web API
  exposure, and frontend integration.
version: 1.0.0
author: Marc
tags:
  - power-platform
  - knowledge-base
  - knowledgearticle
  - dataverse
  - content-management
---

# Knowledge Base Article Management

> **Trigger**: "Set up knowledge base articles" or "Integrate KB articles"

Manage Dataverse `knowledgearticle` records: create, update, publish, and
surface them on a Power Pages Code Site.

## Prerequisites

- Dataverse environment with KB enabled (default in most environments).
- Azure CLI for token acquisition.
- For Power Pages integration: site deployed with Web API enabled.

## Before You Start

1. Use the **Dataverse MCP** to check existing knowledge articles:
   ```
   GET /api/data/v9.2/knowledgearticles?$top=5&$select=title,statecode
   ```
2. Use the **Microsoft Learn MCP** to verify the knowledge article state
   machine and supported transitions.

## Step-by-Step Procedure

### Phase 1: Understand Article Lifecycle

| State | StateCode | StatusCode | Description |
|---|---|---|---|
| Draft | 0 | 1 | Initial state, editable |
| Approved | 1 | 5 | Ready for publishing |
| Scheduled | 2 | 6 | Scheduled for publish |
| Published | 3 | 7 | Live, visible to users |
| Expired | 4 | 10 | Past expiration date |
| Archived | 5 | 12 | Permanently retired |

### Phase 2: Create Articles via OData

```powershell
$envUrl = "https://<your-org>.crm.dynamics.com"
$token = az account get-access-token --resource $envUrl --query accessToken -o tsv
$headers = @{
  "Authorization" = "Bearer $token"
  "Content-Type"  = "application/json"
  "OData-MaxVersion" = "4.0"
  "OData-Version" = "4.0"
  "Prefer" = "return=representation"
}

$article = @{
  title = "How to reset your password"
  description = "Step-by-step guide for password reset"
  content = "<h2>Password Reset</h2><p>Follow these steps...</p>"
  keywords = "password, reset, account"
  articlepublicnumber = "KB-001"
} | ConvertTo-Json

$result = Invoke-RestMethod -Uri "$envUrl/api/data/v9.2/knowledgearticles" `
  -Headers $headers -Method Post -Body $article
```

### Phase 3: Publish Articles

Articles must transition through states: Draft -> Approved -> Published.

```powershell
# Set to approved (requires custom action or direct update)
$approveBody = @{
  statecode = 1
  statuscode = 5
} | ConvertTo-Json

Invoke-RestMethod -Uri "$envUrl/api/data/v9.2/knowledgearticles($($result.knowledgearticleid))" `
  -Headers $headers -Method Patch -Body $approveBody

# Publish
$publishBody = @{
  statecode = 3
  statuscode = 7
} | ConvertTo-Json

Invoke-RestMethod -Uri "$envUrl/api/data/v9.2/knowledgearticles($($result.knowledgearticleid))" `
  -Headers $headers -Method Patch -Body $publishBody
```

### Phase 3b: Sync Content to Rich Text Store

> **IMPORTANT**: Articles created via the API will show **blank content** in the
> Dynamics 365 form editor until the user clicks Refresh. This is because the
> platform's `msdyn_contentstore` blob column is not populated by direct API writes.

After publishing, re-PATCH each article to trigger the content store sync:

```powershell
# Read current content then write it back with sync flag reset
$getHeaders = @{
  "Authorization"    = "Bearer $token"
  "OData-MaxVersion" = "4.0"
  "OData-Version"    = "4.0"
}
$article = Invoke-RestMethod `
  -Uri "$envUrl/api/data/v9.2/knowledgearticles($articleId)?`$select=content" `
  -Headers $getHeaders -Method Get

$syncBody = @{
  content = $article.content
  msdyn_iscontentsyncedtostore = $false
} | ConvertTo-Json -Depth 5

$patchHeaders = @{
  "Authorization"    = "Bearer $token"
  "Content-Type"     = "application/json"
  "OData-MaxVersion" = "4.0"
  "OData-Version"    = "4.0"
  "If-Match"         = "*"
}
Invoke-RestMethod `
  -Uri "$envUrl/api/data/v9.2/knowledgearticles($articleId)" `
  -Headers $patchHeaders -Method Patch -Body $syncBody
```

For batch operations, write a small `Sync-ArticleContentStore.ps1` helper that
iterates the article IDs and runs the read-then-PATCH pair against each one.

### Phase 4: Enable Web API Access

Create site settings for the knowledgearticle table (see setup-permissions skill):

```powershell
New-SiteSetting -Name "Webapi/knowledgearticle/enabled" -Value "true" -SiteId $siteId
New-SiteSetting -Name "Webapi/knowledgearticle/fields" -Value "knowledgearticleid,title,description,content,keywords,articlepublicnumber,statecode,statuscode,createdon,modifiedon" -SiteId $siteId
```

**Remember**: `knowledgearticleid` MUST be in the fields list.

### Phase 5: Create Table Permission (OData API)

Use the `New-TablePermission` function from the **setup-permissions** skill:

```powershell
New-TablePermission -Name "Knowledge Article - Global Read" `
  -EntityLogicalName "knowledgearticle" `
  -SiteId $siteId `
  -WebRoleIds @($anonRoleId, $authRoleId)
```

After creating, restart the site from the maker portal.

> **Fallback**: If not picked up after restart, create manually in
> Design Studio > Security > Table permissions (Global scope, Read,
> assigned to Anonymous + Authenticated roles).

### Phase 6: Frontend Integration

Create `src/services/knowledgeArticles.ts`:

```typescript
import { apiRequest } from './powerPagesApi';

export interface KnowledgeArticle {
  knowledgearticleid: string;
  title: string;
  description?: string;
  content?: string;
  keywords?: string;
  articlepublicnumber?: string;
  statecode: number;
  createdon: string;
}

export const knowledgeArticleService = {
  list: () =>
    apiRequest<{ value: KnowledgeArticle[] }>(
      '/knowledgearticles?$filter=statecode eq 3&$orderby=createdon desc'
    ),

  get: (id: string) =>
    apiRequest<KnowledgeArticle>(`/knowledgearticles(${id})`),

  search: (query: string) =>
    apiRequest<{ value: KnowledgeArticle[] }>(
      `/knowledgearticles?$filter=contains(title,'${query}') and statecode eq 3`
    ),
};
```

### Phase 7: Build KB Page Component

Create a knowledge base page that:
1. Lists published articles with search/filter.
2. Shows article detail with HTML content rendering.
3. Supports keyword-based navigation.

> **Detail page pattern**: For the article detail route and component
> (handling `/knowledgebase/article/{number}/en-us` URLs), see the
> [knowledge-base-public-links-for-spa](../knowledge-base-public-links-for-spa/SKILL.md) skill.

## Common Mistakes & Warnings

- **Primary key in fields list** -- `knowledgearticleid` MUST be in the
  `Webapi/knowledgearticle/fields` setting or you get 403 errors.
- **Filter for published only** -- Always filter `statecode eq 3` in portal
  queries to avoid showing draft/archived articles.
- **HTML content rendering** -- Article `content` field contains HTML. Use
  `dangerouslySetInnerHTML` in React (sanitize first!) or a sanitization library.
- **State transitions** -- You cannot jump directly from Draft to Published.
  Must go Draft -> Approved -> Published.
- **Article public number** -- `articlepublicnumber` is auto-generated if not
  provided. Set it explicitly for clean KB numbering.
