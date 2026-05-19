---
name: power-platform-fetchxml-builder
description: >
  Use when the user asks to "build a FetchXML query", "query Dataverse",
  "create a fetch query", "filter records", or "aggregate data". Builds FetchXML
  queries with filters, linked entities, aggregation, and OData conversion.
version: 1.0.0
author: Marc
tags:
  - power-platform
  - fetchxml
  - dataverse
  - query
  - odata
---

# Build FetchXML Queries

> **Trigger**: "Build a FetchXML query for [requirement]"

Construct FetchXML queries for Dataverse data retrieval. Covers basic queries,
filters, linked entities (joins), aggregation, and conversion to OData.

## Step-by-Step Procedure

### Phase 1: Understand the Requirement

1. Clarify which table(s) to query.
2. Identify the columns needed.
3. Determine filter criteria.
4. Check if joins (linked entities) are needed.
5. Check if aggregation (count, sum, avg) is needed.

### Phase 2: Basic Query Structure

```xml
<fetch top="50">
  <entity name="incident">
    <attribute name="incidentid" />
    <attribute name="title" />
    <attribute name="createdon" />
    <order attribute="createdon" descending="true" />
  </entity>
</fetch>
```

### Phase 3: Add Filters

```xml
<fetch>
  <entity name="incident">
    <attribute name="incidentid" />
    <attribute name="title" />
    <filter type="and">
      <condition attribute="statuscode" operator="eq" value="1" />
      <condition attribute="createdon" operator="last-x-days" value="30" />
    </filter>
  </entity>
</fetch>
```

**Common Filter Operators:**

| Operator | Description | Example |
|---|---|---|
| `eq` | Equals | `value="1"` |
| `ne` | Not equals | `value="0"` |
| `gt` / `lt` | Greater/less than | `value="100"` |
| `ge` / `le` | Greater/less or equal | `value="50"` |
| `like` | Pattern match | `value="%search%"` |
| `in` | In list | Multiple `<value>` children |
| `null` / `not-null` | Null check | No value needed |
| `last-x-days` | Date range | `value="30"` |
| `this-month` | Current month | No value needed |
| `on-or-after` | Date comparison | `value="2024-01-01"` |

### Phase 4: Linked Entities (Joins)

```xml
<fetch>
  <entity name="incident">
    <attribute name="title" />
    <link-entity name="account" from="accountid" to="customerid" link-type="inner">
      <attribute name="name" alias="accountname" />
      <filter>
        <condition attribute="name" operator="like" value="Contoso%" />
      </filter>
    </link-entity>
  </entity>
</fetch>
```

**Link Types:**

| Type | Description |
|---|---|
| `inner` | Only matching records |
| `outer` | All records (left join) |
| `exists` | Filter only (no columns) |
| `any` | Exists in subquery |

### Phase 5: Aggregation

```xml
<fetch aggregate="true">
  <entity name="incident">
    <attribute name="incidentid" alias="count" aggregate="count" />
    <attribute name="statuscode" alias="status" groupby="true" />
  </entity>
</fetch>
```

**Aggregate Functions:** `count`, `countcolumn`, `sum`, `avg`, `min`, `max`

### Phase 6: Convert to OData (if needed)

FetchXML can be passed as a query parameter to the OData endpoint:

```
GET /api/data/v9.2/incidents?fetchXml=<url-encoded-fetchxml>
```

**FetchXML to OData equivalents:**

| FetchXML | OData |
|---|---|
| `<attribute name="x" />` | `$select=x` |
| `<filter><condition ... />` | `$filter=x eq 1` |
| `<order attribute="x" />` | `$orderby=x` |
| `top="50"` | `$top=50` |
| `<link-entity ...>` | `$expand=relationship` |

## Common Mistakes & Warnings

- **Always alias linked entity attributes** -- Without aliases, column names
  collide between tables.
- **Use `link-type="outer"`** for optional relationships -- Inner joins exclude
  records with no related record.
- **Aggregate queries require `aggregate="true"`** on the `<fetch>` element.
- **URL-encode FetchXML** when passing to OData -- Special characters like `<`,
  `>`, `&` must be encoded.
- **Max 5000 records per page** -- Use paging cookies for large result sets.
- **`top` is an attribute of `<fetch>`** -- Not a child element.
