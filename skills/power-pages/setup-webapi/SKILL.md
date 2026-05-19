---
name: power-pages-setup-webapi
description: >
  Use when the user asks to "connect to the API", "set up Web API",
  "wire up data", "fetch data", "create API services", or "integrate Dataverse".
  Configures the Power Pages /_api/ Web API endpoint and generates TypeScript
  services, types, and React hooks for Dataverse CRUD operations.
version: 1.0.0
author: Marc
applyTo: "powerpages.config.json,**/powerpages.config.json"
tags:
  - power-pages
  - web-api
  - dataverse
  - typescript
  - react
---

# Set Up Power Pages Web API Integration

> **Trigger**: "Wire up the Web API for [table name]"

Generate a typed, DRY Web API integration layer that talks to `/_api/` endpoints
on Power Pages. This covers site settings, TypeScript types, shared API client,
per-table services, and optional React hooks.

## Prerequisites

- **Site deployed** at least once (`pac pages upload-code-site`).
- **Table permissions** created via OData API or Design Studio (see setup-permissions skill).
- **Site settings** for Web API enabled (see setup-permissions skill).
- Anti-forgery token available in the portal runtime (automatic on deployed sites).

## Critical Limitations

> **Power Pages Web API does NOT support Dataverse actions or functions.**
> Operations like `CloseIncident` (resolve a case), `QualifyLead`, `WinOpportunity`,
> etc. CANNOT be called through `/_api/`. Only CRUD (Create, Read, Update, Delete)
> and association operations are supported.
>
> **State transitions that require actions will fail** with error `0x80040216` /
> `9004010D`. For incidents: resolving (statecode=1) requires `CloseIncident` action
> and is NOT possible via PATCH. **Cancelling** (statecode=2, statuscode=6) works
> via direct PATCH. Add any closing notes BEFORE the state change.

## Before You Start

1. Use the **Dataverse MCP** to check existing `Webapi/*` site settings for the site.
2. Use the **Microsoft Learn MCP** to verify the latest `/_api/` endpoint syntax.

## Step-by-Step Procedure

### Phase 1: Create the Shared API Client

Create `src/services/powerPagesApi.ts`:

> **IMPORTANT**: Power Pages code sites do NOT inject a
> `<meta name="__RequestVerificationToken">` tag. You MUST fetch the token
> from the `/_layout/tokenhtml` endpoint. The old `meta` tag approach will
> silently return an empty string and every POST/PATCH/DELETE will fail with
> "Request validation failed".

> **IMPORTANT**: ALL `/_api/` requests MUST include OData headers:
> `Accept: application/json`, `OData-MaxVersion: 4.0`, `OData-Version: 4.0`.
> Without these, **optionset/picklist fields** (e.g. `prioritycode`, `statuscode`,
> `caseorigincode`) are **silently dropped** on POST — the record is created
> but without the optionset value, no error returned. This is per the
> [MS docs](https://learn.microsoft.com/en-us/power-pages/configure/web-api-http-requests-handle-errors#http-headers).
> Add these headers to the shared API helper so every call includes them.

```typescript
let cachedToken: string | null = null;

async function fetchAntiForgeryToken(): Promise<string> {
  if (cachedToken) return cachedToken;
  try {
    const response = await fetch('/_layout/tokenhtml');
    if (!response.ok) return '';
    const html = await response.text();
    const valueString = 'value="';
    const terminalString = '" />';
    const valueIndex = html.indexOf(valueString);
    if (valueIndex === -1) return '';
    cachedToken = html.substring(
      valueIndex + valueString.length,
      html.indexOf(terminalString, valueIndex)
    );
    return cachedToken || '';
  } catch {
    return '';
  }
}

export function clearTokenCache(): void {
  cachedToken = null;
}

const API_BASE = '/_api';

interface ApiOptions {
  method?: string;
  body?: unknown;
  headers?: Record<string, string>;
}

export async function apiRequest<T>(
  path: string,
  options: ApiOptions = {}
): Promise<T> {
  const { method = 'GET', body, headers = {} } = options;
  const token = await fetchAntiForgeryToken();

  const res = await fetch(`${API_BASE}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'OData-MaxVersion': '4.0',
      'OData-Version': '4.0',
      __RequestVerificationToken: token,
      ...headers,
    },
    body: body ? JSON.stringify(body) : undefined,
  });

  if (!res.ok) {
    // Token may have expired — clear cache and retry once for write ops
    if (res.status === 403 && method !== 'GET' && cachedToken) {
      cachedToken = null;
      const freshToken = await fetchAntiForgeryToken();
      const retry = await fetch(`${API_BASE}${path}`, {
        method,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'OData-MaxVersion': '4.0',
          'OData-Version': '4.0',
          __RequestVerificationToken: freshToken,
          ...headers,
        },
        body: body ? JSON.stringify(body) : undefined,
      });
      if (retry.ok) {
        if (retry.status === 204) return {} as T;
        return retry.json();
      }
      const retryError = await retry.json().catch(() => ({}));
      throw new Error(
        retryError?.error?.message ?? `API ${method} ${path} failed: ${retry.status}`
      );
    }
    const error = await res.json().catch(() => ({}));
    throw new Error(
      error?.error?.message ?? `API ${method} ${path} failed: ${res.status}`
    );
  }

  if (res.status === 204) return {} as T;
  return res.json();
}
```

### Phase 2: Generate TypeScript Types

For each Dataverse table, create a type file in `src/types/`:

```typescript
// src/types/incident.ts
export interface Incident {
  incidentid: string;
  title: string;
  description?: string;
  statuscode: number;
  createdon: string;
  _customerid_value?: string;
}
```

**Rules:**
- Use the logical column names from Dataverse.
- Lookup fields use the `_fieldname_value` pattern.
- Date fields are ISO strings.
- All fields except the primary key should be optional unless required by business logic.

### Phase 3: Generate Per-Table Services

Create `src/services/<table>.ts`:

```typescript
import { apiRequest } from './powerPagesApi';
import type { Incident } from '../types/incident';

const ENTITY = 'incidents';

export const incidentService = {
  list: (select?: string[], filter?: string) => {
    const params = new URLSearchParams();
    if (select) params.set('$select', select.join(','));
    if (filter) params.set('$filter', filter);
    const qs = params.toString();
    return apiRequest<{ value: Incident[] }>(
      `/${ENTITY}${qs ? '?' + qs : ''}`
    );
  },

  get: (id: string) =>
    apiRequest<Incident>(`/${ENTITY}(${id})`),

  create: (data: Partial<Incident>) =>
    apiRequest<Incident>(`/${ENTITY}`, {
      method: 'POST',
      body: data,
    }),

  update: (id: string, data: Partial<Incident>) =>
    apiRequest<void>(`/${ENTITY}(${id})`, {
      method: 'PATCH',
      body: data,
    }),

  delete: (id: string) =>
    apiRequest<void>(`/${ENTITY}(${id})`, {
      method: 'DELETE',
    }),
};
```

### Phase 4: Generate React Hooks (if React project)

Create `src/hooks/use<Table>.ts`:

```typescript
import { useState, useEffect, useCallback } from 'react';
import { incidentService } from '../services/incidents';
import type { Incident } from '../types/incident';

export function useIncidents() {
  const [data, setData] = useState<Incident[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  const refresh = useCallback(async () => {
    setLoading(true);
    try {
      const result = await incidentService.list();
      setData(result.value);
    } catch (e) {
      setError(e instanceof Error ? e : new Error(String(e)));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { refresh(); }, [refresh]);

  return { data, loading, error, refresh };
}
```

### Phase 5: Mock Data for Local Development

When running locally (not on Power Pages), the `/_api/` endpoint is not
available. Create mock handlers or use the existing `mockData.ts` service:

```typescript
// In the API client, detect local dev:
const isLocalDev = window.location.hostname === 'localhost';

// If local dev, return mock data instead of calling /_api/
```

### Phase 6: Integration

1. Import services/hooks into page components.
2. Replace any hardcoded or mock data with API calls.
3. Add loading states and error boundaries.
4. Test with mock data locally, verify on deployed site.

## Required Site Settings (Webapi/*)

These MUST exist as `powerpagecomponent` type 9 records:

| Setting Name | Value |
|---|---|
| `Webapi/<entity>/enabled` | `true` |
| `Webapi/<entity>/fields` | Comma-separated logical column names (MUST include primary key!) |
| `Webapi/<entity>/disableodatafilter` | `false` |

**See the setup-permissions skill for creating these.**

## Common Mistakes & Warnings

- **403 "AttributePermissionIsMissing"** -- A field in `$select` is not listed
  in `Webapi/<entity>/fields`. The **primary key field** (e.g., `incidentid`)
  MUST also be included in the fields list.
- **404 "Resource not found for segment"** -- The `Webapi/<entity>/enabled`
  site setting is missing or belongs to a different site.
- **Anti-forgery token is empty locally** -- Expected; use mock data for local dev.
- **NEVER use `meta[name="__RequestVerificationToken"]`** -- Code sites do
  NOT inject that meta tag. Always fetch the token from `/_layout/tokenhtml`.
  The meta-tag pattern only works on traditional portals.
- **Entity name is plural** -- `/_api/` uses the plural OData entity set name
  (e.g., `incidents` not `incident`).
- **Lookup fields need `@odata.bind`** on POST/PATCH -- e.g.,
  `"customerid_account@odata.bind": "/accounts(guid)"`.
