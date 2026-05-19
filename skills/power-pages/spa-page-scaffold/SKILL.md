---
name: spa-page-scaffold
description: >
  Use when creating a new SPA page for a Power Pages Code Site. Generates a robust
  React component with all required patterns: auth check, error handling, null-safe
  Dataverse field access, debug console logging, loading/error states, and proper
  typing. Prevents blank-white-screen bugs from the start.
---

# SPA Page Scaffold for Power Pages Code Sites

> **Trigger**: "add a new page", "create a page for X", "new listing page",
> "scaffold a detail page", "add a CRUD page"

## When to Use

When building any new page component in a Power Pages SPA that reads from
the `/_api/` Web API. This scaffold bakes in all patterns learned from
production bugs.

## Page Template — Listing Page

```tsx
import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { apiRequest, isLocalDev, type ODataResponse } from '../services/powerPagesApi';
import { getPortalUser } from '../services/auth';
// import { mockItems } from '../services/mockData';  // uncomment for local dev
// import type { YourEntity } from '../types/dataverse';

// interface YourEntity { ... }

export default function YourListingPage() {
  console.debug('[YourPage] Component rendering');
  const [items, setItems] = useState<YourEntity[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [search, setSearch] = useState('');

  useEffect(() => {
    console.debug('[YourPage] useEffect fired. isLocalDev:', isLocalDev);

    if (isLocalDev) {
      // setItems(mockItems);
      setLoading(false);
      return;
    }

    // Auth check — always verify user before API call
    const user = getPortalUser();
    console.debug('[YourPage] getPortalUser():', JSON.stringify(user));
    if (!user?.contactId) {
      console.debug('[YourPage] No contactId — showing sign-in prompt');
      setError('Please sign in to view this page.');
      setLoading(false);
      return;
    }

    // Build OData query — always scope to contact
    const select = 'field1,field2,field3,createdon';
    const filter = `_customerid_value eq ${user.contactId}`;
    const url = `/yourentity?$select=${select}&$filter=${filter}&$orderby=createdon desc`;
    console.debug('[YourPage] Fetching:', url);

    apiRequest<ODataResponse<YourEntity>>(url)
      .then((r) => {
        console.debug('[YourPage] Response. Count:', r.value?.length);
        if (r.value?.length) {
          console.debug('[YourPage] First item:', JSON.stringify(r.value[0]));
        }
        setItems(r.value ?? []);
      })
      .catch((e) => {
        console.error('[YourPage] API error:', e);
        setError(e instanceof Error ? e.message : String(e));
      })
      .finally(() => {
        console.debug('[YourPage] Loading complete');
        setLoading(false);
      });
  }, []);

  // NULL-SAFE filtering — always use (field ?? '') before .toLowerCase()
  const filtered = items.filter((item) => {
    const q = search.toLowerCase();
    return (item.field1 ?? '').toLowerCase().includes(q) ||
           (item.field2 ?? '').toLowerCase().includes(q);
  });

  if (loading) return <div className="page"><div className="container"><p>Loading…</p></div></div>;
  if (error) return <div className="page"><div className="container"><p className="error-msg">{error}</p></div></div>;

  return (
    <div className="page">
      <div className="container">
        <h1>Your Page Title</h1>
        {/* NULL-SAFE display — always use ?? 'fallback' for nullable fields */}
        {filtered.map((item) => (
          <div key={item.primaryKeyField}>
            <h3>{item.field1 ?? '(No title)'}</h3>
            <p>{item.field2 ?? '—'}</p>
          </div>
        ))}
        {filtered.length === 0 && <p>No records found.</p>}
      </div>
    </div>
  );
}
```

## Page Template — Detail Page

```tsx
import { useEffect, useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import { apiRequest, isLocalDev, type ODataResponse } from '../services/powerPagesApi';
// import type { YourEntity } from '../types/dataverse';

export default function YourDetailPage() {
  const { id } = useParams<{ id: string }>();
  console.debug('[YourDetail] Rendering. id:', id);
  const [item, setItem] = useState<YourEntity | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    if (!id) return;
    console.debug('[YourDetail] useEffect. Fetching record:', id);

    if (isLocalDev) {
      // setItem(mockItems.find(i => i.id === id) ?? null);
      setLoading(false);
      return;
    }

    const fullSelect = 'field1,field2,description,createdon';
    const fallbackSelect = 'field1,field2,createdon';

    // 403 fallback pattern — retry without restricted fields
    const fetchRecord = async (): Promise<YourEntity> => {
      try {
        return await apiRequest<YourEntity>(
          `/yourentity(${id})?$select=${fullSelect}`
        );
      } catch (err) {
        if (err instanceof Error && err.message.includes('403')) {
          console.warn('[YourDetail] 403 — retrying without description');
          return apiRequest<YourEntity>(
            `/yourentity(${id})?$select=${fallbackSelect}`
          );
        }
        throw err;
      }
    };

    fetchRecord()
      .then((r) => {
        console.debug('[YourDetail] Record loaded:', JSON.stringify(r));
        setItem(r);
      })
      .catch((e) => {
        console.error('[YourDetail] Load error:', e);
        setError(e instanceof Error ? e.message : String(e));
      })
      .finally(() => setLoading(false));
  }, [id]);

  if (loading) return <div className="page"><div className="container"><p>Loading…</p></div></div>;
  if (error) return <div className="page"><div className="container"><p className="error-msg">{error}</p></div></div>;
  if (!item) return <div className="page"><div className="container"><p>Not found.</p></div></div>;

  return (
    <div className="page">
      <div className="container">
        <Link to="/yourpage">← Back</Link>
        {/* NULL-SAFE display */}
        <h1>{item.field1 ?? '(No title)'}</h1>
        <p>{item.description ?? ''}</p>
      </div>
    </div>
  );
}
```

## TypeScript Interface Pattern

**Always** type Dataverse string fields as `string | null`:

```typescript
export interface YourEntity {
  primarykeyfield: string;       // Primary keys are always non-null
  title: string | null;          // ← CAN be null from Dataverse
  description?: string | null;   // Optional AND nullable
  statuscode: number;            // Choice fields are numeric, non-null
  createdon: string;             // System dates are always populated
}
```

## Checklist for Every New Page

- [ ] Auth check with `getPortalUser()` — "sign in" message if no contactId
- [ ] Contact-scoped filter (`_customerid_value eq {contactId}`)
- [ ] All Dataverse string fields typed as `string | null`
- [ ] Null-coalesce before `.toLowerCase()` / any string method
- [ ] Null fallback in JSX: `{field ?? 'fallback'}`
- [ ] `console.debug('[PageName] ...')` at: component render, useEffect, API URL, response shape, errors
- [ ] 403 fallback on detail pages (retry without restricted fields)
- [ ] Loading state shown while fetching
- [ ] Error state with user-visible message
- [ ] Route added to App.tsx
- [ ] Mock data path for local dev
- [ ] **React ErrorBoundary in main.tsx** — wraps `<App />` to catch crashes and show errors instead of blank white screen (see deploy skill for template)

---

## Knowledge Base Article Pattern (Proven Working)

When building a Knowledge Base feature, **always** use this pattern (proven
across ProjectB, ProjectC, and ProjectA):

### URL Pattern

Link to articles using `articlepublicnumber`, NOT `knowledgearticleid`:

```
/knowledgebase/article/:articleNumber/:lang
```

Example: `/knowledgebase/article/KA-01001/en-us`

### Why `articlepublicnumber` Instead of GUID

- Human-readable URLs (good for sharing / bookmarks)
- Stable across environments (the public number is the same in dev and prod)
- Matches the Power Pages native KB URL pattern

### List Page → Detail Page Links

Use React Router `<Link>`, **never** `<a href>` with external URLs or `#`:

```tsx
import { Link } from 'react-router-dom';

// In the card title:
<Link to={`/knowledgebase/article/${article.articlepublicnumber}/en-us`}>
  {article.title ?? '(No title)'}
</Link>

// In the card footer "Read article →" link:
<Link
  to={`/knowledgebase/article/${article.articlepublicnumber}/en-us`}
  className="kb-read-link"
>
  Read article →
</Link>
```

**Do NOT** use `externalLink`, `msdyn_externalreferenceid`, or `#` as the
href — the article content is stored in the Dataverse `content` field and
should be rendered inline.

### Detail Page — Fetch by `articlepublicnumber`

```tsx
const { articleNumber } = useParams<{ articleNumber: string }>();

// Fetch via OData filter (not by GUID):
apiFetch<ODataResponse<KnowledgeArticleRecord>>(
  `/_api/knowledgearticles?$select=knowledgearticleid,title,description,content,keywords,articlepublicnumber,statecode,createdon,modifiedon&$filter=articlepublicnumber eq '${encodeURIComponent(articleNumber)}' and statecode eq 3&$top=1`,
)
  .then((r) => setArticle(r.value[0] ?? null))
```

**Key points:**
- `$select` MUST include `content` (the HTML body of the article)
- `$filter` MUST include `statecode eq 3` (published articles only)
- Use `encodeURIComponent` on the article number
- Take `$top=1` since public numbers are unique

### Detail Page — Render Content

Use `dangerouslySetInnerHTML` for KB article content (it's authored HTML):

```tsx
{article.content ? (
  <div
    className="kb-article-content"
    dangerouslySetInnerHTML={{ __html: article.content }}
  />
) : (
  <p className="text-muted">No content available for this article.</p>
)}
```

### Route in App.tsx

```tsx
import KBArticleDetail from './pages/KBArticleDetail';

<Route path="/knowledgebase/article/:articleNumber/:lang" element={<KBArticleDetail />} />
```

### Service — No Separate `getArticle` Function Needed

The detail page fetches directly via `apiFetch` with an inline OData URL.
This avoids adding a function to the KB service that would only be used once.
