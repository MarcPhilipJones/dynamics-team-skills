---
name: code-apps-reference
description: >
  Comprehensive reference for building, extending, and deploying Power Apps Code
  Apps with Dataverse connectivity and Microsoft Fluent UI v9. Use when scaffolding
  a Code App, connecting to Dataverse, adding connectors, querying via OData/FetchXML,
  CRUD operations, bulk ops, Power Apps Search, column-level security, Fluent UI
  patterns, deployment/ALM (new `power-apps` npm CLI or legacy `pac code`), or
  troubleshooting Code App issues.
version: 2.0.0
author: Marc
tags:
  - power-apps
  - code-apps
  - dataverse
  - react
  - typescript
  - vite
  - fluent-ui
  - pac-cli
---

# Power Apps Code Apps — Skill Guide

> **v2.0.0 — GA + new `power-apps` npm CLI, version/known-issue corrections (June 2026)**

> **Comprehensive reference for building, extending, and deploying Power Apps Code Apps with Dataverse connectivity and Microsoft Fluent UI.**
>
> Source: Microsoft Learn — [Power Apps Code Apps](https://learn.microsoft.com/en-us/power-apps/developer/code-apps/) + [Data Platform](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/) (verified June 2026)

> **⚡ Status & tooling (June 2026):**
>
> - **Code Apps are Generally Available (GA).** They are no longer in preview.
> - **New `power-apps` npm CLI is now the recommended tooling.** Shipped inside the
>   `@microsoft/power-apps` package (v1.0.4+), it replaces the Power Platform CLI's
>   `pac code` commands, which are **deprecated and will be removed in a future release**.
>   CLI evolution: `pac code` → `npx power-apps` → global **`power-apps`** command.
> - **Latest package version is `@microsoft/power-apps@1.2.2`** (June 2026). The
>   GitHub starter templates still pin `^1.0.3` — **bump to `^1.2.2` after scaffolding**
>   (see [Known Issues](#16-known-issues--version-gotchas)).
> - The AI assistant plugin (Claude / GitHub Copilot) moved to
>   [microsoft/power-platform-skills](https://github.com/microsoft/power-platform-skills).

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Prerequisites & Environment Setup](#2-prerequisites--environment-setup)
3. [Project Structure](#3-project-structure)
4. [Power Apps Code Apps — How It Works](#4-power-apps-code-apps--how-it-works)
5. [Connecting to Dataverse (Official SDK Method)](#5-connecting-to-dataverse-official-sdk-method)
6. [Dataverse Data Platform — Core Concepts](#6-dataverse-data-platform--core-concepts)
7. [Querying Data — OData, FetchXML, and SQL](#7-querying-data--odata-fetchxml-and-sql)
8. [Data Operations — CRUD](#8-data-operations--crud)
9. [Bulk Operations](#9-bulk-operations)
10. [Search Integration](#10-search-integration)
11. [Security & Column-Level Security](#11-security--column-level-security)
12. [Microsoft Fluent UI v9 — Usage Patterns](#12-microsoft-fluent-ui-v9--usage-patterns)
13. [Deployment & ALM](#13-deployment--alm)
14. [Common Patterns & Best Practices](#14-common-patterns--best-practices)
15. [Troubleshooting](#15-troubleshooting)
16. [Known Issues & Version Gotchas](#16-known-issues--version-gotchas)
17. [Quick Command Reference](#17-quick-command-reference)

---

## 1. Architecture Overview

```
┌────────────────────────────────────────────────────────────────┐
│                      Power Apps Host                           │
│   (Manages auth, app loading, runtime hosting)                 │
├────────────────────────────────────────────────────────────────┤
│                   @microsoft/power-apps SDK                    │
│   (Generated services/models, context API, connector access)   │
├────────────────────────────────────────────────────────────────┤
│                     Your React Application                     │
│   ┌──────────┐  ┌──────────────┐  ┌────────────────────┐      │
│   │ Fluent UI│  │ React Router │  │ Generated Services │      │
│   │ v9       │  │  (pages)     │  │ (SDK auto-gen)     │      │
│   └──────────┘  └──────────────┘  └────────────────────┘      │
│                                                                │
│   Built with: Vite + TypeScript + React 19                     │
└────────────────────────────────────────────────────────────────┘
         │                                    │
         ▼                                    ▼
   ┌──────────┐                    ┌──────────────────┐
   │ Browser  │                    │ Microsoft        │
   │ (SPA)    │                    │ Dataverse        │
   └──────────┘                    │ (OData v4)       │
                                   └──────────────────┘
```

**Three layers:**

| Layer               | Purpose                                                   |
| ------------------- | --------------------------------------------------------- |
| **Your code**       | React/TypeScript app built with Vite                      |
| **Power Apps SDK**  | `@microsoft/power-apps` — APIs, generated models/services |
| **Power Apps Host** | Manages end-user Entra auth, app loading, runtime hosting |

**Key files:**

| File                | Purpose                                                                 |
| ------------------- | ----------------------------------------------------------------------- |
| `power.config.json` | Generated by SDK — metadata for connections and publishing              |
| `src/generated/`    | Auto-generated typed TypeScript models and services                     |
| `vite.config.ts`    | Vite config with `powerApps()` plugin from `@microsoft/power-apps-vite` |

---

## 2. Prerequisites & Environment Setup

### Required Software

| Tool                       | Version   | Purpose                                                    |
| -------------------------- | --------- | ---------------------------------------------------------- |
| **Node.js**                | LTS (20+) | JavaScript runtime                                         |
| **Git**                    | Latest    | Version control                                            |
| **VS Code**                | Latest    | IDE                                                        |
| **`@microsoft/power-apps`** | 1.2.2+    | Power Apps client library **+ new `power-apps` npm CLI**   |
| **PAC CLI** (legacy)       | Latest    | Power Platform CLI (`pac code` — **deprecating**)          |
| **Azure CLI** (opt.)       | Latest    | For Azure operations                                       |

> **CLI evolution — which command do I use?**
>
> | Era | Command | Status |
> | --- | ------- | ------ |
> | Original | `pac code init / add-data-source / push` | **Deprecated** — still works for now |
> | Transitional | `npx power-apps <cmd>` | Works (runs the package CLI without global install) |
> | **Current (recommended)** | `power-apps <cmd>` (global install) | ✅ Use this |
>
> The new npm CLI ships in `@microsoft/power-apps` v1.0.4+ and has four commands:
> `init`, `run`, `push`, `find-dataverse-api`. Data-source management
> (`add-data-source`, `list-datasets`, etc.) is still performed via `pac code`
> until those move to the npm CLI.

### Power Apps CLI Authentication

The new `power-apps` CLI authenticates you automatically on `power-apps init`
(sign in with your Power Platform account when prompted). For data-source
commands that still use `pac`, authenticate as below:

```powershell
# Authenticate to your Power Platform environment (pac — for add-data-source etc.)
pac auth create --url https://<your-org>.crm.dynamics.com

# Or use existing auth profile
pac auth list
pac auth select --index <N>

# Select environment
pac env select --environment <environment-id>
```

### Environment Requirements

| Requirement                        | Notes                                                |
| ---------------------------------- | ---------------------------------------------------- |
| **Code Apps enabled**              | PP Admin Centre → Environments → Settings → Features |
| **Power Apps Premium licence**     | Required for end-users                               |
| **Dataverse database provisioned** | Required for data connectivity                       |

### First-Time Project Setup

**Recommended — scaffold from an official template, then use the `power-apps` npm CLI:**

```powershell
# 1. Scaffold from a Microsoft template (starter = React + Vite + Tailwind +
#    Tanstack Query + React Router; vite = minimal React + Vite)
npx degit microsoft/PowerAppsCodeApps/templates/starter#main my-app
cd my-app

# 2. IMPORTANT: the template still pins @microsoft/power-apps ^1.0.3 — bump it
npm install @microsoft/power-apps@latest

# 3. Install the CLI globally + remaining dependencies
npm install -g @microsoft/power-apps   # provides the `power-apps` command
npm install

# 4. Initialise the code app (authenticates automatically; interactive or flags)
power-apps init                                                  # interactive
# power-apps init --display-name "<Your App Name>" --environment-id <env-id>

# 5. Add Dataverse table(s) as data source(s) — still via pac code for now
pac code add-data-source -a dataverse -t <table-logical-name>

# 6. Run locally
npm run dev
```

**Legacy (deprecated `pac code`) flow — still functional:**

```powershell
cd <your-app-folder>
npm install
pac code init --displayName "<Your App Name>"
pac code add-data-source -a dataverse -t <table-logical-name>
npm run dev
```

---

## 3. Project Structure

```
<your-app>/
├── index.html                  # Single-page app entry point
├── package.json                # Dependencies & scripts
├── vite.config.ts              # Vite + powerApps() plugin
├── tsconfig.json               # TypeScript project references
├── tsconfig.app.json           # App compilation settings
├── tsconfig.node.json          # Node/Vite compilation settings
├── eslint.config.js            # ESLint configuration
├── skill.md                    # ← This file — development guide
├── power.config.json           # (Generated) Power Platform config
├── public/
│   └── vite.svg                # App icon
└── src/
    ├── main.tsx                # App bootstrap — FluentProvider + React root
    ├── App.tsx                 # Router and page layout
    ├── App.css                 # Minimal global styles
    ├── index.css               # CSS reset using Fluent design tokens
    ├── components/             # Reusable UI components
    ├── pages/                  # Route-level page components
    ├── services/               # Data access facades (mock → SDK)
    ├── hooks/                  # Custom React hooks
    ├── types/                  # App-specific TypeScript types
    └── generated/              # (Auto-generated by pac code add-data-source)
        ├── models/
        │   └── <Table>Model.ts   # Typed interfaces for each table
        └── services/
            └── <Table>Service.ts # CRUD methods for each table
```

> **Template note:** Two official templates exist. The **`starter`** template
> (recommended) ships with React, Vite, **Tailwind CSS**, Radix UI, Tanstack
> Query, and React Router. The **`vite`** template is a minimal React + Vite
> setup. The Fluent UI v9 patterns in this guide map to the **`FluentSample`**
> sample app — if you scaffold from `starter`, you'll be using Tailwind/Radix
> rather than Fluent, so adapt the UI sections accordingly.

---

## 4. Power Apps Code Apps — How It Works

### What Are Code Apps?

Power Apps Code Apps let developers bring Power Apps capabilities into custom web apps built in a code-first IDE (VS Code). Build with popular frameworks (React, Vue) while keeping full control over UI and logic, then deploy to Power Platform.

**Key capabilities:**

- **Microsoft Entra authentication** built in — no auth code required
- **Access to 1,500+ Power Platform connectors** callable from TypeScript
- **Managed platform policies** — DLP, Conditional Access, app sharing limits
- **Simplified deployment** via `pac code push`

### Published Code Security

> Published code is hosted on a publicly accessible endpoint — **never store sensitive data in app code.** Authentication, secrets, and data access are managed by the Power Apps host.

### Runtime Context

```typescript
import { getContext } from "@microsoft/power-apps/app";

const ctx = await getContext();
ctx.app.appId; // Current app ID
ctx.app.environmentId; // Power Platform environment ID
ctx.app.queryParams; // URL query parameters
ctx.user.fullName; // Signed-in user's name
ctx.user.objectId; // Entra object ID
ctx.user.tenantId; // Tenant ID
ctx.user.userPrincipalName; // UPN (e.g. user@contoso.com)
ctx.host.sessionId; // Session ID (changes each open)
```

### Current Limitations (GA — verified June 2026)

- No Storage Shared Access Signature (SAS) IP restriction support
- No Power Platform Git integration (yet)
- Not supported in **Power Apps for Windows**
- No Power BI **data** integration (`PowerBIIntegration` function) — but a code app
  **can be embedded in Power BI reports** via the Power Apps Visual
- No SharePoint **forms** integration (SharePoint data operations *are* supported)
- Service Principals (SPN) cannot create or become owners of code apps
- Chrome/Edge block localhost requests by default (since Dec 2025) — grant Local
  Network Access during dev, or use `allow="local-network-access"` on iframes

> **Now supported (previously listed as limitations — corrected June 2026):**
>
> - **Power Apps mobile** — code apps now run on mobile (an Android layout bug is
>   being fixed; see [Known Issues](#16-known-issues--version-gotchas)).
> - **Dataverse actions & functions** — see [Add a Dataverse action or function](https://learn.microsoft.com/en-us/power-apps/developer/code-apps/how-to/add-dataverse-action-function)
>   (`power-apps find-dataverse-api`).
> - **Power Automate flows** — see [Add flows](https://learn.microsoft.com/en-us/power-apps/developer/code-apps/how-to/add-flows).
> - **Azure SQL, SharePoint operations, and Copilot Studio** connections.

---

## 5. Connecting to Dataverse (Official SDK Method)

### The Right Way — `pac code add-data-source`

This project uses the **official Dataverse connection method** via the Power Apps SDK. This is NOT raw OData/REST API calls — the SDK generates strongly-typed TypeScript services automatically.

```powershell
# Step 1: Add a Dataverse table as a data source
pac code add-data-source -a dataverse -t <table-logical-name>
# e.g. pac code add-data-source -a dataverse -t contact

# This generates:
#   src/generated/models/<Table>Model.ts   — typed interface
#   src/generated/services/<Table>Service.ts — CRUD operations
```

### Generated Service API

After running the command above, the generated service provides typed CRUD methods. Example using `contact`:

```typescript
import { ContactsService } from "./generated/services/ContactsService";
import type { Contacts } from "./generated/models/ContactsModel";

// Retrieve multiple records
const result = await ContactsService.getAll({
    select: ["fullname", "emailaddress1", "telephone1"],
    filter: "statecode eq 0", // Active records only
    orderBy: ["fullname asc"],
    top: 50,
});

// Retrieve single record
const record = await ContactsService.get(recordId);

// Create a new record
const newRecord = await ContactsService.create({
    firstname: "Chris",
    lastname: "Walker",
    emailaddress1: "chris@contoso.com",
} as Omit<Contacts, "contactid">);

// Update a record
await ContactsService.update(recordId, {
    jobtitle: "Senior Engineer",
});

// Delete a record
await ContactsService.delete(recordId);
```

The same pattern applies to any Dataverse table — `AccountsService`, `IncidentsService`, etc.

### Adding Other Data Sources

```powershell
# Add additional Dataverse tables
pac code add-data-source -a dataverse -t account
pac code add-data-source -a dataverse -t incident    # Cases
pac code add-data-source -a dataverse -t contact

# Add a Power Platform connector (e.g. Office 365 Users)
pac code add-data-source -a "shared_office365users" -c "<connectionId>"

# Add tabular connector (e.g. SQL)
pac code add-data-source -a "shared_sql" -c "<connectionId>" \
  -t "[dbo].[TableName]" -d "server.db.net,dbname"

# List available connections
pac connection list

# Discover datasets/tables for a connector
pac code list-datasets -a <apiId> -c <connectionId>
pac code list-tables -a <apiId> -c <connectionId> -d <datasetName>

# Delete a data source (no refresh command — delete and re-add)
pac code delete-data-source -a "shared_sql" -ds "TableName"
```

> **Actions & functions:** To call a Dataverse action or function, use the new
> npm CLI's `power-apps find-dataverse-api` command to discover and generate the
> typed wrapper. See [Add a Dataverse action or function](https://learn.microsoft.com/en-us/power-apps/developer/code-apps/how-to/add-dataverse-action-function).
>
> **Caution (issue [#366](https://github.com/microsoft/PowerAppsCodeApps/issues/366)):**
> re-running `add-data-source` can drop existing connector entries (e.g.
> `shared_logicflows`) from `src/generated/dataSourcesInfo.ts`. Back up that file
> before adding new sources.

### Connection References (for ALM portability)

```powershell
pac code add-data-source -a <apiName> -cr <connectionReferenceLogicalName> -s <solutionID>
```

### Migration Path: Mock → Generated Service

Code Apps often ship with a mock/local data implementation in `src/services/`. After connecting Dataverse:

1. Run `pac code add-data-source -a dataverse -t <table>`
2. Open your service file (e.g. `src/services/<table>Service.ts`)
3. Replace mock data calls with the generated service imports
4. Remove or comment out the mock data and mock implementations

---

## 6. Dataverse Data Platform — Core Concepts

### Data Access Methods (from Microsoft docs)

| Method             | Use When                                               |
| ------------------ | ------------------------------------------------------ |
| **Code Apps SDK**  | Building Power Apps Code Apps (this project)           |
| **Web API**        | RESTful OData v4 — any language with HTTP + OAuth 2.0  |
| **SDK for .NET**   | Plug-ins, custom workflow activities, .NET client apps |
| **SDK for Python** | Data science, automation, AI workflows (preview)       |
| **TDS Endpoint**   | SQL queries via Power Query or SSMS (preview)          |

### OData v4 Fundamentals

Dataverse implements OData v4. Key conventions:

| Concept          | Example                                                         |
| ---------------- | --------------------------------------------------------------- |
| Entity set       | `contacts`, `accounts`, `incidents`                             |
| Single entity    | `contacts(guid)`                                                |
| Property select  | `$select=fullname,emailaddress1`                                |
| Filter           | `$filter=statecode eq 0`                                        |
| Order            | `$orderby=fullname asc`                                         |
| Top/Skip         | `$top=50&$skip=0`                                               |
| Expand (related) | `$expand=account_primary_contact($select=name)`                 |
| Annotations      | `Prefer: odata.include-annotations="*"` — gets formatted values |
| Count            | `$count=true`                                                   |

### Key OData Operators for Filters

| Operator     | Description        | Example                                    |
| ------------ | ------------------ | ------------------------------------------ |
| `eq`         | Equal              | `statecode eq 0`                           |
| `ne`         | Not equal          | `statuscode ne 2`                          |
| `gt`         | Greater than       | `createdon gt 2026-01-01T00:00:00Z`        |
| `ge`         | Greater or equal   | `revenue ge 100000`                        |
| `lt`         | Less than          | `numberofemployees lt 50`                  |
| `le`         | Less or equal      | `revenue le 500000`                        |
| `and`        | Logical AND        | `statecode eq 0 and statuscode eq 1`       |
| `or`         | Logical OR         | `city eq 'London' or city eq 'Birmingham'` |
| `not`        | Logical NOT        | `not contains(fullname, 'test')`           |
| `contains`   | String contains    | `contains(fullname, 'Chris')`              |
| `startswith` | String starts with | `startswith(lastname, 'W')`                |
| `endswith`   | String ends with   | `endswith(emailaddress1, '@contoso.com')`  |

### Payload Size Limits

| Limit                     | Value                                       |
| ------------------------- | ------------------------------------------- |
| Max request payload       | 128 MB                                      |
| Max response payload      | 1 GB                                        |
| Default page size         | 5,000 records (OData)                       |
| Service protection limits | 6,000 requests per user per 5-minute window |

---

## 7. Querying Data — OData, FetchXML, and SQL

### OData Query Patterns (Web API)

```
GET /api/data/v9.2/contacts?$select=fullname,emailaddress1&$filter=statecode eq 0&$top=50&$orderby=fullname asc
```

**With annotations** (for formatted values):

```
Header: Prefer: odata.include-annotations="*"
```

### FetchXML

FetchXML is Dataverse's XML-based query language. Used in plug-ins, reports, and advanced queries.

```xml
<fetch top="50">
  <entity name="contact">
    <attribute name="fullname" />
    <attribute name="emailaddress1" />
    <filter type="and">
      <condition attribute="statecode" operator="eq" value="0" />
      <condition attribute="address1_city" operator="eq" value="Birmingham" />
    </filter>
    <order attribute="fullname" />
    <!-- Join to parent account -->
    <link-entity name="account"
                 from="accountid"
                 to="parentcustomerid"
                 link-type="outer"
                 alias="account">
      <attribute name="name" />
    </link-entity>
  </entity>
</fetch>
```

**Key FetchXML concepts:**

- `link-entity` supports: `inner`, `outer`, `exists`, `in`, `any`, `not any`, `all`, `not all`, `matchfirstrowusingcrossapply`
- Maximum 15 `link-entity` elements per query
- Maximum 500 `condition` + `link-entity` elements per query
- `datasource="bin"` attribute retrieves deleted records from recycle bin

### SQL (TDS Endpoint)

```sql
SELECT fullname, emailaddress1
FROM contact
WHERE statecode = 0
ORDER BY fullname ASC
```

> **Note:** The Dataverse MCP preview server uses T-SQL with a hard limit of 20 records per query. For larger datasets, use OData or the Python/NET SDK.

### Paging Best Practices

- **Always include a column with unique values** in your `$orderby` to ensure deterministic paging
- Use the `@odata.nextLink` returned in responses to fetch subsequent pages
- FetchXML uses paging cookies — store the cookie from the previous response
- Without deterministic ordering, the same record can appear in multiple pages
- Good: `$orderby=fullname asc,contactid asc` (fullname + unique key)
- Bad: `$orderby=statecode` (non-unique, records can overlap pages)

---

## 8. Data Operations — CRUD

> The examples below use `contact` as an illustrative table. The same patterns apply to any Dataverse table — substitute the appropriate generated service and model.

### Create

```typescript
// Via generated service
await ContactsService.create({
  firstname: "Chris",
  lastname: "Walker",
  emailaddress1: "chris@contoso.com"
} as Omit<Contacts, 'contactid'>);

// Via Web API
POST /api/data/v9.2/contacts
{
  "firstname": "Chris",
  "lastname": "Walker",
  "emailaddress1": "chris@contoso.com"
}
```

### Retrieve

```typescript
// Single record via generated service
const contact = await ContactsService.get(contactId);

// Multiple records
const contacts = await ContactsService.getAll({
    select: ["fullname", "emailaddress1"],
    filter: "statecode eq 0",
    top: 50,
});
```

### Update

```typescript
// Via generated service — send ONLY changed fields
await ContactsService.update(contactId, {
  jobtitle: "Senior Engineer"
});

// Via Web API
PATCH /api/data/v9.2/contacts(guid)
{
  "jobtitle": "Senior Engineer"
}
```

> **Important:** Only include the fields you are changing. Sending all fields overwrites everything.

### Delete

```typescript
await ContactsService.delete(contactId);

// Via Web API
DELETE /api/data/v9.2/contacts(guid)
```

### Upsert

Upsert creates a record if it doesn't exist, or updates it if it does. Useful for integration scenarios with alternate keys.

```
PATCH /api/data/v9.2/contacts(guid)
// With header: If-Match: * → update only
// With header: If-None-Match: * → create only
// No header → upsert (create or update)
```

---

## 9. Bulk Operations

For high-volume scenarios, use bulk operation messages:

| Message          | Description                                        |
| ---------------- | -------------------------------------------------- |
| `CreateMultiple` | Creates multiple records in a single request       |
| `UpdateMultiple` | Updates multiple records in a single request       |
| `UpsertMultiple` | Creates or updates multiple records in one request |
| `DeleteMultiple` | Deletes multiple records (elastic tables only)     |

### Standard Tables vs Elastic Tables

| Aspect                | Standard Tables                     | Elastic Tables                    |
| --------------------- | ----------------------------------- | --------------------------------- |
| **Records per batch** | 100–1,000 (larger = more efficient) | Send 100 at a time, parallelise   |
| **On error**          | Entire batch rolls back             | Partial success possible          |
| **Backend**           | Azure SQL (transactions)            | Azure Cosmos DB (no transactions) |

### API Limits

| Limit                              | Value                                       |
| ---------------------------------- | ------------------------------------------- |
| Service protection: requests       | 6,000 / user / server / 5-min window        |
| Service protection: execution time | 20 min / user / server / 5-min window       |
| Individual operation (bulk)        | Each item in Targets counts as one API call |

---

## 10. Search Integration

Dataverse Search provides fast, relevance-ranked cross-table search.

### Three Search Operations

| Operation            | Purpose                   |
| -------------------- | ------------------------- |
| `searchquery`        | Full search results page  |
| `searchsuggest`      | Suggestions as user types |
| `searchautocomplete` | Autocomplete input field  |

### Search Query Example

```json
POST /api/search/v2.0/query
{
  "search": "Chris Walker",
  "entities": "[{\"name\":\"contact\",\"selectColumns\":[\"fullname\",\"emailaddress1\"]}]",
  "filter": "statecode eq 0",
  "count": true,
  "top": 20
}
```

### Search Syntax

| Syntax             | Example          | Description           |
| ------------------ | ---------------- | --------------------- | ----------- |
| AND                | `gas +safety`    | Both terms required   |
| OR                 | `gas             | water`                | Either term |
| NOT                | `gas -leak`      | Exclude term          |
| Wildcards          | `Walk*`          | Trailing wildcard     |
| Exact match        | `"Chris Walker"` | Phrase match          |
| Fuzzy (Lucene)     | `Walkar~`        | Misspelling tolerance |
| Proximity (Lucene) | `"gas safety"~5` | Terms within 5 words  |

### Rate Limits

- 1 request per user per second
- 150 requests per organisation per minute
- Returns `429 Too Many Requests` with `Retry-After` header

---

## 11. Security & Column-Level Security

### Row-Level Security

- Code Apps run in **user context** — Dataverse row-level security is automatically enforced
- The signed-in user only sees records their security roles allow
- No additional security code needed in the app

### Column-Level Security

Dataverse supports securing individual columns:

1. **Mark column as secured**: Set `IsSecured = true` on column metadata
2. **Create Field Security Profiles**: Associate users/teams with field permissions
3. **Field Permissions**: `CanCreate`, `CanRead`, `CanUpdate` per column

When a column is secured and the user doesn't have read access:

- The value is returned as `null` (default)
- With Display Masked Data feature: a masked string is returned

### Masked Data (Preview)

Columns can be configured with masking rules to show partial data:

- e.g., `****-****-1234` for an ID number
- Configure via `MaskingRule` and `AttributeMaskingRule` tables
- Retrieve unmasked data with `UnMaskedData` optional parameter

---

## 12. Microsoft Fluent UI v9 — Usage Patterns

### Setup (Already Configured)

The app wraps the React root in `FluentProvider`:

```tsx
// src/main.tsx
import { FluentProvider, webLightTheme } from "@fluentui/react-components";

<FluentProvider theme={webLightTheme}>
    <App />
</FluentProvider>;
```

### Key Components Used

```tsx
import {
    // Layout
    Card,
    CardHeader,
    CardPreview,
    // Data Display
    Table,
    TableHeader,
    TableRow,
    TableCell,
    TableBody,
    TableHeaderCell,
    DataGrid,
    DataGridHeader,
    DataGridRow,
    DataGridCell,
    DataGridBody,
    DataGridHeaderCell,
    Badge,
    Avatar,
    Tag,
    // Input
    Input,
    Textarea,
    Field,
    Dropdown,
    Option,
    Combobox,
    Button,
    CompoundButton,
    ToggleButton,
    SearchBox,
    // Navigation
    TabList,
    Tab,
    Breadcrumb,
    BreadcrumbItem,
    // Feedback
    Spinner,
    ProgressBar,
    MessageBar,
    Toast,
    Toaster,
    Dialog,
    DialogTrigger,
    DialogSurface,
    DialogTitle,
    DialogBody,
    DialogActions,
    // Layout
    Toolbar,
    ToolbarButton,
    Divider,
} from "@fluentui/react-components";
```

### Icons

```tsx
import {
    PersonRegular,
    PersonAddRegular,
    EditRegular,
    DeleteRegular,
    SaveRegular,
    SearchRegular,
    FilterRegular,
    ChevronLeftRegular,
    ChevronRightRegular,
    HomeRegular,
    ContactCardRegular,
    MailRegular,
    PhoneRegular,
    BuildingRegular,
    LocationRegular,
    CalendarRegular,
    ArrowLeftRegular,
    MoreHorizontalRegular,
} from "@fluentui/react-icons";
```

### Design Tokens (CSS Variables)

Fluent UI v9 exposes design tokens as CSS custom properties:

```css
/* Available globally when FluentProvider wraps the app */
var(--colorBrandBackground)          /* Primary brand colour */
var(--colorBrandForeground1)         /* Brand text colour */
var(--colorNeutralBackground1)       /* Default background */
var(--colorNeutralBackground2)       /* Secondary background */
var(--colorNeutralForeground1)       /* Default text colour */
var(--colorNeutralForeground2)       /* Secondary text */
var(--colorNeutralStroke1)           /* Border colour */
var(--colorBrandForegroundLink)      /* Link colour */
var(--fontFamilyBase)                /* Default font */
var(--fontSizeBase200)               /* Small text */
var(--fontSizeBase300)               /* Body text */
var(--fontSizeBase400)               /* Subheading */
var(--fontSizeBase500)               /* Heading */
var(--fontSizeBase600)               /* Large heading */
var(--spacingHorizontalM)            /* Medium horizontal spacing */
var(--spacingVerticalM)              /* Medium vertical spacing */
var(--borderRadiusMedium)            /* Standard border radius */
var(--shadow4)                       /* Elevation shadow */
```

### Theme Switching

```tsx
import { webLightTheme, webDarkTheme, teamsDarkTheme } from "@fluentui/react-components";

// In FluentProvider:
<FluentProvider theme={isDark ? webDarkTheme : webLightTheme}>
```

### makeStyles Pattern

```tsx
import { makeStyles, tokens } from "@fluentui/react-components";

const useStyles = makeStyles({
    container: {
        padding: tokens.spacingHorizontalL,
        display: "flex",
        flexDirection: "column",
        gap: tokens.spacingVerticalM,
    },
    card: {
        maxWidth: "600px",
        boxShadow: tokens.shadow4,
    },
});

function MyComponent() {
    const styles = useStyles();
    return <div className={styles.container}>...</div>;
}
```

---

## 13. Deployment & ALM

### Pre-Publish Checklist

Before running `pac code push`, verify all prerequisites:

| Prerequisite               | Command                       | Expected                                   |
| -------------------------- | ----------------------------- | ------------------------------------------ |
| Node.js LTS                | `node --version`              | v20+ (tested with v24.13.0)                |
| npm                        | `npm --version`               | v9+ (tested with v11.6.2)                  |
| Git                        | `git --version`               | Any recent version                         |
| PAC CLI / power-apps        | `pac auth list`              | Active profile on target environment       |
| Active environment         | `pac env who`                 | Must match `environmentId` in power.config |
| `power.config.json` exists | `Test-Path power.config.json` | True                                       |
| Dependencies installed     | `Test-Path node_modules`      | True (run `npm install` if not)            |
| `@microsoft/power-apps` 1.2.2+ | `npm ls @microsoft/power-apps` | Not pinned to old 1.0.3                  |
| TypeScript compiles        | `npx tsc -b`                  | No errors                                  |
| Vite build succeeds        | `npm run build`               | `dist/` folder created                     |

### Build & Deploy

```powershell
# Build the production bundle
npm run build

# Deploy to Power Platform — NEW npm CLI (recommended)
power-apps push

# Legacy (deprecated) — still works
pac code push --solutionName <YourSolution>

# Combined build + deploy (if configured in package.json)
npm run deploy    # e.g. runs: npm run build && power-apps push
```

### First Publish Behaviour

On the first push (when `appId` is `null` in `power.config.json`):

1. The CLI creates a **new Code App** in the target environment
2. Assigns a new `appId` GUID
3. **Automatically updates `power.config.json`** with the new `appId` — no manual edit needed
4. Subsequent pushes update the same app rather than creating duplicates

> **Note**: An early `pac code push` may show a transient
> `CodePushMakeSolutionAwareErrorMessage` error and retry automatically — this is
> normal and the push succeeds on retry.

### Adding to a Solution

> **CRITICAL LEARNING (2 March 2026):** The `--solutionName` flag on `pac code push` does **not** retroactively add an existing app to a solution. If the app was first created _without_ `--solutionName`, subsequent pushes with `--solutionName CodeApps` silently succeed but leave the solution empty. The same applies to `pac solution add-solution-component` — it returns "CanvasApp does not exist" because Code Apps are not stored in the `canvasapp` entity.
>
> **Correct approach:** Add the app to a solution via the **Power Apps maker portal UI**:

1. Go to [make.powerapps.com](https://make.powerapps.com/) → Solutions → select your solution
2. Click **Add existing** → **App** → **Code app**
3. Select the app from the list

This is the Microsoft-documented approach per the [ALM docs for Code Apps](https://learn.microsoft.com/en-us/power-apps/developer/code-apps/how-to/alm#add-to-a-solution-in-power-apps-ui).

**To avoid this issue on future apps:** Always specify `--solutionName` on the **very first** push, or set a **preferred solution** in the environment (PP Admin Centre → Environments → Settings → Features → Preferred solution).

### ALM Pipeline (Dev → Test → Prod)

Use **Power Platform Pipelines** for managed deployment across environments:

1. Export solution from Dev environment
2. Import as managed to Test
3. Test thoroughly
4. Import as managed to Prod

### Hiding the Power Apps Header

Append `?hideNavBar=true` to the app URL.

### Current ALM Limitations

- No source code integration with Power Platform Git
- Manual export/import still required for cross-environment moves
- **Solution movement has known bugs** — e.g. errors on solution *unpack* with
  code apps, and `add-data-source` can drop existing connector entries from
  `dataSourcesInfo.ts`. See [Known Issues](#16-known-issues--version-gotchas).

---

## 14. Common Patterns & Best Practices

### Pattern: Data Access Facade

Always wrap Dataverse calls in a service layer rather than calling the generated service directly from components:

```
components → <table>Service.ts → <Table>Service (generated) → Dataverse
```

This gives you:

- A single place to swap mock data for real data
- Error handling and retry logic in one location
- Type mapping between generated types and your app types

### Pattern: Optimistic Updates

```typescript
// 1. Update local state immediately (optimistic)
setRecords((prev) =>
    prev.map((r) => (r.id === id ? { ...r, ...changes } : r)),
);

// 2. Send update to Dataverse
try {
    await updateRecord(id, changes);
} catch (error) {
    // 3. Revert on failure
    setRecords((prev) =>
        prev.map((r) => (r.id === id ? originalRecord : r)),
    );
    // Show error toast
}
```

### Pattern: Search with Debounce

```typescript
import { useDebouncedValue } from "./hooks/useDebouncedValue";

const [searchTerm, setSearchTerm] = useState("");
const debouncedSearch = useDebouncedValue(searchTerm, 300);

useEffect(() => {
    if (debouncedSearch) {
        fetchRecords(`contains(name, '${debouncedSearch}')`);
    }
}, [debouncedSearch]);
```

### Best Practices from Dataverse Docs

1. **Use `$select` always** — Only request the columns you need. Reduces payload and improves performance.

2. **Filter on indexed columns** — `statecode`, `createdon`, `modifiedon`, primary keys are always indexed.

3. **Deterministic paging** — Always include a unique column in `$orderby` when paging.

4. **Update only changed fields** — Don't send the entire record on PATCH, only the changed properties.

5. **Prefer batch operations for bulk work** — `CreateMultiple`/`UpdateMultiple` are significantly faster than individual operations.

6. **Handle 429 responses** — Implement retry with the `Retry-After` header value.

7. **Don't guess entity/field names** — Use `list_tables` and `describe_table` from MCP, or query `EntityDefinitions` to verify names.

8. **Formatted values for display** — Always request `Prefer: odata.include-annotations="*"` when you need display-friendly values for choices, lookups, and dates.

### Recycle Bin (Deleted Record Recovery)

- Records can be recovered within 30 days (configurable)
- Query deleted records: add `datasource='bin'` to FetchXML
- Restore with the `Restore` message
- Always restore related records before primary records

---

## 15. Troubleshooting

### Common Build Errors

| Error                                     | Cause                                  | Fix                                                    |
| ----------------------------------------- | -------------------------------------- | ------------------------------------------------------ |
| `Cannot find module '../generated/...'`   | `pac code add-data-source` not run yet | Run `pac code add-data-source -a dataverse -t <table>` |
| `powerApps() plugin error`                | `power.config.json` missing            | Run `power-apps init` (or legacy `pac code init`)      |
| `Module not found: @microsoft/power-apps` | npm packages not installed             | Run `npm install`                                      |
| `Chrome blocks localhost`                 | Local Network Access permission        | User must grant access when prompted                   |

### Common Runtime Errors

| Error                   | Cause                       | Fix                                               |
| ----------------------- | --------------------------- | ------------------------------------------------- |
| `401 Unauthorized`      | Authentication expired      | Re-login via Power Apps host or `pac auth create` |
| `403 Forbidden`         | Insufficient security roles | Check user's Dataverse security roles             |
| `404 Not Found`         | Entity/record doesn't exist | Verify entity name and record GUID                |
| `429 Too Many Requests` | Service protection limit    | Implement retry with `Retry-After` header         |
| `413 Payload Too Large` | Request > 128 MB            | Reduce batch size or payload                      |

### Dataverse-Specific Gotchas

1. **Polymorphic lookups** (e.g., `parentcustomerid`) cannot be used in `$select` — Dataverse returns them automatically as `_parentcustomerid_value`.

2. **Boolean fields** — Dataverse stores as `true`/`false`, but formatted values show Yes/No.

3. **Choice/OptionSet fields** — The raw value is an integer. Use the `@OData.Community.Display.V1.FormattedValue` annotation to get the label.

4. **Lookup columns in `$orderby`** — Results are sorted by the primary name of the related table, not the GUID.

5. **`fullname` is computed** — You cannot set it directly. Set `firstname` and `lastname` instead.

---

## 16. Known Issues & Version Gotchas

> Verified against the [PowerAppsCodeApps repo issues](https://github.com/microsoft/PowerAppsCodeApps/issues) and Microsoft Learn, June 2026.

### Version pinning (do this on every new app)

- **Starter templates ship outdated.** Both `templates/starter` and
  `templates/vite` pin `@microsoft/power-apps` at **`^1.0.3`**, but the latest
  stable is **`1.2.2`**. Run `npm install @microsoft/power-apps@latest` right
  after scaffolding — the old pin misses critical fixes.
- `@microsoft/power-apps-vite` latest is **`1.0.2`** (the template pin is current here).
- **The Code Apps plugin reports version `1.0.0` and does not appear to
  auto-update.** Don't rely on automatic patches — update packages manually and
  reinstall the CLI (`npm install -g @microsoft/power-apps@latest`).

### Open repository issues to be aware of

| Area                 | Issue                                                                            | Notes                                                                                |
| -------------------- | -------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| **Mobile (Android)** | [#364](https://github.com/microsoft/PowerAppsCodeApps/issues/364) iframe `100vh` | Android nav bar overlaps bottom content; fix in progress by MS                       |
| **Mobile (iOS)**     | [#373](https://github.com/microsoft/PowerAppsCodeApps/issues/373)                | Crash on Power Apps mobile (iOS) — `platformSpecificResourcesVersion` undefined       |
| **ALM / solutions**  | [#369](https://github.com/microsoft/PowerAppsCodeApps/issues/369)                | Errors unpacking solutions containing code apps                                       |
| **Connector gen.**   | [#366](https://github.com/microsoft/PowerAppsCodeApps/issues/366)                | `add-data-source` drops existing `shared_logicflows` entry from `dataSourcesInfo.ts` |
| **Connector gen.**   | [#348](https://github.com/microsoft/PowerAppsCodeApps/issues/348) / [#352](https://github.com/microsoft/PowerAppsCodeApps/issues/352) | SharePoint (`AADSTS65002`) and SQL `@envvar:` data-source failures                   |
| **Modelling**        | [#365](https://github.com/microsoft/PowerAppsCodeApps/issues/365)                | Cannot create N:N (many-to-many) relations via tooling                               |

> Mitigations: pin `@microsoft/power-apps@1.2.2`, back up `dataSourcesInfo.ts`
> before running `add-data-source`, and prefer the maker portal UI for adding
> code apps to solutions (see [§13 ALM](#13-deployment--alm)). Check the repo's
> **Closed** issues tab — several of these may already be fixed by the time you read this.

---

## 17. Quick Command Reference

```powershell
# ── Project Setup (NEW power-apps npm CLI — recommended) ──
npx degit microsoft/PowerAppsCodeApps/templates/starter#main my-app  # scaffold
npm install @microsoft/power-apps@latest          # bump from pinned 1.0.3 -> 1.2.2
npm install -g @microsoft/power-apps              # install the `power-apps` CLI
npm install                                       # install dependencies
power-apps init                                   # init (auto-auth; or --display-name / --environment-id)
pac code add-data-source -a dataverse -t <table>  # add Dataverse table (still via pac)

# ── Development ──────────────────────────────────
npm run dev                                  # Local dev server (power-apps run)
npm run lint                                 # Run ESLint
npm run build                                # Production build (tsc -b && vite build)

# ── Deployment ───────────────────────────────────
power-apps push                              # Deploy (NEW CLI, recommended)
pac code push --solutionName <Solution>      # Deploy (legacy, deprecated)

# ── Data Source Management (pac code — deprecating) ──
pac code add-data-source -a dataverse -t <table>       # Add Dataverse table
pac code delete-data-source -a dataverse -ds <ds>      # Remove a data source
pac connection list                                     # List connections

# ── Debugging & Inspection ───────────────────────
pac env select                               # Select environment
pac auth list                                # List auth profiles
pac solution list                            # List solutions
```

---

## References

| Resource                         | URL                                                                                          |
| -------------------------------- | -------------------------------------------------------------------------------------------- |
| **Data Platform Developer Docs** | https://learn.microsoft.com/en-us/power-apps/developer/data-platform/                        |
| **Code Apps Docs (home)**        | https://learn.microsoft.com/en-us/power-apps/developer/code-apps/                            |
| **Code Apps Overview**           | https://learn.microsoft.com/en-us/power-apps/developer/code-apps/overview                    |
| **npm CLI Quickstart**           | https://learn.microsoft.com/en-us/power-apps/developer/code-apps/how-to/npm-quickstart       |
| **Add Dataverse action/function**| https://learn.microsoft.com/en-us/power-apps/developer/code-apps/how-to/add-dataverse-action-function |
| **Add flows**                    | https://learn.microsoft.com/en-us/power-apps/developer/code-apps/how-to/add-flows            |
| **Connect to Dataverse**         | https://learn.microsoft.com/en-us/power-apps/developer/code-apps/how-to/connect-to-dataverse |
| **@microsoft/power-apps (npm)**  | https://www.npmjs.com/package/@microsoft/power-apps                                          |
| **Fluent UI v9 React**           | https://react.fluentui.dev/                                                                  |
| **Fluent UI v9 Icons**           | https://react.fluentui.dev/?path=/docs/icons-catalog--docs                                   |
| **Web API Reference**            | https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/                 |
| **FetchXML Reference**           | https://learn.microsoft.com/en-us/power-apps/developer/data-platform/fetchxml/               |
| **Bulk Operations**              | https://learn.microsoft.com/en-us/power-apps/developer/data-platform/bulk-operations         |
| **Dataverse Search**             | https://learn.microsoft.com/en-us/power-apps/developer/data-platform/search/                 |
| **Code Apps GitHub Samples**     | https://github.com/microsoft/PowerAppsCodeApps/tree/main/samples                             |
| **Code Apps Templates**          | https://github.com/microsoft/PowerAppsCodeApps/tree/main/templates                           |
| **Code Apps Repo Issues**        | https://github.com/microsoft/PowerAppsCodeApps/issues                                        |
| **AI Assistant Plugin (moved)**  | https://github.com/microsoft/power-platform-skills                                           |
| **PAC CLI Reference**            | https://learn.microsoft.com/en-us/power-platform/developer/cli/introduction                  |
