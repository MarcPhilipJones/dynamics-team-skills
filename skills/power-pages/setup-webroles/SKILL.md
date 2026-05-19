---
name: power-pages-setup-webroles
description: >
  Use when the user asks to "create web roles", "set up roles", "configure user roles",
  "add anonymous role", or "add authenticated role". Creates web role YAML files
  for Power Pages Code Sites.
version: 1.0.0
author: Marc
applyTo: "powerpages.config.json,**/powerpages.config.json"
tags:
  - power-pages
  - web-roles
  - security
  - authorization
---

# Create Web Roles

> **Trigger**: "Create web roles for the site"

Define web roles for a Power Pages Code Site. Web roles control which table
permissions, web page access rules, and features are available to each user type.

## Prerequisites

- Site deployed at least once.
- PAC CLI authenticated.

## Step-by-Step Procedure

### Phase 1: Discovery

1. Ask the user what roles their site needs.
2. Standard roles for most sites:
   - **Anonymous Users** -- unauthenticated visitors (read-only public content)
   - **Authenticated Users** -- any logged-in user (baseline access)
   - **Administrator** -- full access to all content and settings
3. Present proposed roles for approval.

### Phase 2: Standard Role Structure

Every Power Pages site needs at minimum:
- **One anonymous role** (assigned to unauthenticated visitors)
- **One authenticated role** (auto-assigned on login)

### Phase 3: Create Roles via Design Studio

> Web roles for Code Sites v2 should be created in **Design Studio**:

1. Open Power Pages Design Studio.
2. Navigate to **Security** > **Web roles**.
3. Click **+ New role**.
4. Configure each role:
   - **Name**: e.g., "Anonymous Users"
   - **Anonymous users role**: Toggle ON for the anonymous role only
   - **Authenticated users role**: Toggle ON for the authenticated role only
5. Save each role.

### Phase 4: Document Roles

Create a `roles.md` in the project root documenting the roles:

```markdown
# Web Roles

| Role | Type | Purpose |
|---|---|---|
| Anonymous Users | Anonymous | Public read access |
| Authenticated Users | Authenticated | Logged-in user access |
| Administrator | Custom | Full access |
```

### Phase 5: Assign to Table Permissions

After creating roles, assign them to table permissions:
1. In Design Studio > Security > Table permissions.
2. Edit each permission.
3. Under **Web roles**, add the appropriate roles.

## Common Mistakes & Warnings

- **Only ONE anonymous role** -- Power Pages supports only one role marked as
  the anonymous users role per site.
- **Only ONE authenticated role** -- Same constraint for the authenticated users role.
- **Roles are not hierarchical** -- A user can have multiple roles, but roles
  don't inherit from each other.
- **Custom roles need manual assignment** -- Only anonymous and authenticated
  roles are auto-assigned. Custom roles must be assigned to contacts manually
  or via workflow.
- **Role names must be unique** per site.
