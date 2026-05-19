---
name: case-listing
description: >
  Use when implementing or debugging a case listing page (incident list/detail) in a
  Power Pages Code Site SPA. Covers authentication checks, contact-scoped queries,
  Web API client setup (credentials, anti-forgery tokens), 403 fallback patterns,
  and OData field selection for incidents and annotations.
---

# Case Listing & Detail Pages for Power Pages SPA Code Sites

> **Trigger**: "cases page is blank", "case list not loading", "add cases page",
> "incidents page white screen", "fix support cases"

Build or fix a cases (incident) listing + detail page in a Power Pages Code Site
that uses a React SPA with the `/_api/` Web API.

## Root Causes of Blank Case Pages

A blank white page on `/cases` is almost always caused by a silent JS error
crashing React before any DOM is rendered. Common causes ranked by likelihood:

### 1. Missing `credentials: 'include'` on fetch calls (CRITICAL)

Power Pages relies on session cookies for authentication. Without
`credentials: 'include'`, the browser does not send the session cookie. The
`/_api/incidents` endpoint returns an HTML login redirect instead of JSON.
`response.json()` throws, the error is uncaught, and the page stays blank.

**Fix pattern** — every `fetch()` call to `/_api/*` MUST include:
```typescript
const res = await fetch(`/_api/${path}`, {
  method,
  headers,
  credentials: 'include',   // ← required for session cookie
  body: body ? JSON.stringify(body) : undefined,
});
```

**Reference**: ProjectB working implementation in `SSENTPortal/src/services/api.ts`.

### 2. Anti-forgery token fetched on GET requests unnecessarily

The `/_layout/tokenhtml` endpoint may redirect to login or fail for anonymous
users. If you fetch the token on every request (including GETs), GETs are
blocked before they even start.

**Fix pattern** — only fetch the anti-forgery token for write operations:
```typescript
const token = method !== 'GET' ? await fetchAntiForgeryToken() : '';
const reqHeaders: Record<string, string> = {
  'Content-Type': 'application/json',
  ...headers,
};
if (token) reqHeaders.__RequestVerificationToken = token;
```

### 3. No authentication check before API call

If the user is not signed in, `/_api/incidents` returns an HTML login page
instead of JSON. The SPA must check for authentication first.

**Fix pattern** — check `getPortalUser()` before calling the API:
```typescript
const user = getPortalUser();
if (!user?.contactId) {
  setError('Please sign in to view your cases.');
  setLoading(false);
  return;
}
```

Portal user is available from:
```typescript
const portalObj = () => (window as any)['Microsoft']?.Dynamic365?.Portal;
const contactId = portalObj()?.User?.contactId;
```

### 4. Missing contact-scoped filter on query

Without filtering by contact, the query returns ALL incidents. If table
permissions are scoped to the user's contact record, a global query returns
403. Even if it succeeds, showing all org incidents is a security issue.

**Fix pattern** — filter by `_customerid_value`:
```typescript
const filter = `_customerid_value eq ${user.contactId}`;
apiRequest<ODataResponse<Incident>>(
  `/incidents?$select=${fields}&$filter=${filter}&$orderby=createdon desc`
)
```

## Required Dataverse Configuration

### Site Settings (powerpagecomponent type 9)

These must exist in Dataverse for the site. Check/create via API or Design Studio:

| Setting Name | Value | Purpose |
|---|---|---|
| `Webapi/incident/enabled` | `true` | Enable Web API for incidents |
| `Webapi/incident/fields` | `*` | Allow all fields (use wildcard to avoid 403 on nav properties) |
| `Webapi/annotation/enabled` | `true` | Enable Web API for notes |
| `Webapi/annotation/fields` | `*` | Allow all annotation fields |

**CRITICAL**: The primary key field (e.g. `incidentid`) MUST be included in the
fields list. Using `*` avoids this footgun entirely.

### Table Permissions (powerpagecomponent type 18)

| Entity | Scope | Privileges | Web Role |
|---|---|---|---|
| incident | Contact | Read | Authenticated Users |
| annotation | Contact (via incident parent) | Create, Read, Write, Append | Authenticated Users |

Contact scope means a user can only read incidents where `_customerid_value`
matches their contact ID.

## CaseDetail: 403 Fallback Pattern

The `description` field is sometimes blocked by field-level security even when
other fields are allowed. Use a fallback pattern:

```typescript
const fetchIncident = async (): Promise<Incident> => {
  try {
    return await apiRequest<Incident>(
      `/incidents(${id})?$select=incidentid,title,description,ticketnumber,...`
    );
  } catch (err) {
    const is403 = err instanceof Error && err.message.includes('403');
    if (is403) {
      console.warn('403 on detail fetch — retrying without description');
      return apiRequest<Incident>(
        `/incidents(${id})?$select=incidentid,title,ticketnumber,...`
      );
    }
    throw err;
  }
};
```

## 5. Null Dataverse Fields Crashing React (CRITICAL)

Dataverse returns `null` for fields that have no value — even fields like `title`
and `ticketnumber` that you'd expect to always be populated. If the SPA calls
`.toLowerCase()` or any string method on a `null` field, React throws:

```
TypeError: Cannot read properties of null (reading 'toLowerCase')
```

Without a top-level error boundary, this = **blank white screen** with zero
visible error for the user.

**Fix pattern 1** — Type Dataverse fields as nullable:
```typescript
export interface Incident {
  incidentid: string;
  title: string | null;       // ← CAN be null from Dataverse
  ticketnumber: string | null; // ← CAN be null from Dataverse
  statuscode: number;
  // ...
}
```

**Fix pattern 2** — Null-coalesce before string operations:
```typescript
// Filtering / searching
const matchSearch = (c.title ?? '').toLowerCase().includes(q) ||
  (c.ticketnumber ?? '').toLowerCase().includes(q);

// CSS class generation
`priority-${(priority ?? 'normal').toLowerCase()}`
```

**Fix pattern 3** — Fallback display text in JSX:
```tsx
<td>{c.title ?? '(No title)'}</td>
<td>{c.ticketnumber ?? '—'}</td>
<h1>{incident.title ?? '(No title)'}</h1>
```

**Rule**: Apply this to ALL Dataverse string fields in ALL entities, not just
incidents. Any column with "Business Required" = No can be null.

## 6. Missing Top-Level React Error Boundary

Without an error boundary wrapping the entire app, any uncaught render error
causes a blank white screen. The AppErrorBoundary should:

- Catch all render errors via `componentDidCatch`
- Log the error and component stack to `console.error` with a `[AppErrorBoundary]` tag
- Display a user-visible fallback: "App crashed — check browser console (F12)"

```tsx
class AppErrorBoundary extends React.Component<{children: React.ReactNode}, {error: Error | null}> {
  state = { error: null as Error | null };
  static getDerivedStateFromError(error: Error) { return { error }; }
  componentDidCatch(error: Error, info: React.ErrorInfo) {
    console.error('[AppErrorBoundary] React render crash:', error);
    console.error('[AppErrorBoundary] Component stack:', info.componentStack);
  }
  render() {
    if (this.state.error) return (
      <div style={{padding:'2rem',textAlign:'center'}}>
        <h1>App crashed — check browser console (F12)</h1>
        <pre style={{color:'red'}}>{this.state.error.message}</pre>
      </div>
    );
    return this.props.children;
  }
}
```

## Debug Logging for Presales (ALWAYS INCLUDE)

This is a presales environment — rapid troubleshooting via browser console is
essential. **Always** include extensive `console.debug()` logging in every
component and service module. This avoids days of blind debugging.

### Logging Standards

- **Prefix all logs** with `[ModuleName]` for easy filtering: `[Cases]`, `[CaseDetail]`,
  `[auth]`, `[powerPagesApi]`, `[main]`, `[Header]`
- **Module load**: Log when each module initializes
- **Component render**: Log at the top of each component function
- **Auth state**: Log the full portal user object and contactId
- **API calls**: Log request URL, method, response status, content-type, response
  shape (keys, array length), and first item preview
- **Error boundaries**: Log caught errors with component stack
- **useEffect**: Log when effects fire and what triggers them
- **Global handlers**: Install `window.onerror` and `window.onunhandledrejection`
  in `main.tsx` to catch unhandled errors

### Example Pattern (API service)
```typescript
console.debug('[powerPagesApi] Module loaded');

async function apiRequest<T>(path: string, opts?: RequestInit): Promise<T> {
  const url = `/_api/${path}`;
  console.debug(`[powerPagesApi] apiRequest ${opts?.method ?? 'GET'} ${url}`);
  const res = await fetch(url, { ...opts, credentials: 'include' });
  console.debug(`[powerPagesApi] Response: ${res.status} ${res.statusText}, content-type: ${res.headers.get('content-type')}`);
  const data = await res.json();
  console.debug(`[powerPagesApi] JSON parsed OK. Keys: ${Object.keys(data).join(',')}`);
  return data as T;
}
```

### Example Pattern (Component)
```typescript
export default function Cases() {
  console.debug('[Cases] Component rendering');
  // ...
  useEffect(() => {
    console.debug('[Cases] useEffect fired. isLocalDev:', isLocalDev);
    const user = getPortalUser();
    console.debug('[Cases] getPortalUser() returned:', JSON.stringify(user));
    // ... API call with logging ...
    apiRequest<ODataResponse<Incident>>(url)
      .then((r) => {
        console.debug('[Cases] API response. Count:', r.value?.length);
        console.debug('[Cases] First item:', JSON.stringify(r.value?.[0]));
      })
      .catch((e) => console.error('[Cases] API error:', e));
  }, []);
}
```

## OData Field Selection Reference

### Incident List Query
```
$select=incidentid,title,ticketnumber,statuscode,prioritycode,casetypecode,createdon
$filter=_customerid_value eq {contactId}
$orderby=createdon desc
```

### Incident Detail Query
```
$select=incidentid,title,description,ticketnumber,statuscode,prioritycode,casetypecode,createdon
```

### Annotations for a Case
```
$select=annotationid,subject,notetext,filename,filesize,mimetype,isdocument,createdon
$filter=_objectid_value eq {incidentId}
$orderby=createdon desc
```

## Status / Priority / Category Mappings

```typescript
const incidentStatusMap: Record<number, string> = {
  1: 'In Progress', 2: 'On Hold', 3: 'Waiting for Details',
  4: 'Researching', 5: 'Problem Solved',
  1000: 'Information Provided', 6: 'Cancelled', 2000: 'Merged',
};
const incidentPriorityMap: Record<number, string> = {
  1: 'High', 2: 'Normal', 3: 'Low',
};
const caseTypeMap: Record<number, string> = {
  1: 'Question', 2: 'Problem', 3: 'Request',
};
```

## Comparison: Working (ProjectB) vs Broken (ProjectC original)

| Aspect | ProjectB (working) | ProjectC (was broken) |
|---|---|---|
| `credentials: 'include'` | Yes | **Missing** |
| Token on GET | Skipped | Fetched (blocks GETs) |
| Auth check before fetch | Yes (`getContactId()`) | **Missing** |
| Contact-scoped filter | `_customerid_value eq {id}` | **Missing** (fetched all) |
| 403 fallback on detail | Yes (retry without description) | **Missing** |
| Separate cases service | Yes (`services/cases.ts`) | Inline in component |

## Checklist

- [ ] `credentials: 'include'` on every `fetch()` to `/_api/*`
- [ ] Anti-forgery token only fetched for non-GET methods
- [ ] Auth check before API call — show "sign in" message if not authenticated
- [ ] Filter incidents by `_customerid_value eq {contactId}`
- [ ] `Webapi/incident/enabled = true` site setting exists
- [ ] `Webapi/incident/fields = *` site setting exists
- [ ] Incident table permission exists with Read for Authenticated Users
- [ ] CaseDetail has 403 fallback (retry without description field)
- [ ] Annotation table permission with Create + Read + Write + Append
- [ ] **Null guards**: All Dataverse string fields typed as `string | null`, all `.toLowerCase()` / string methods use `?? ''`, all JSX displays use `?? 'fallback'`
- [ ] **Top-level error boundary**: `AppErrorBoundary` wrapping entire app in `App.tsx`
- [ ] **Debug logging**: `console.debug('[ModuleName] ...')` in every component render, useEffect, API call, and error handler
- [ ] **Global error handlers**: `window.onerror` + `window.onunhandledrejection` in `main.tsx`
