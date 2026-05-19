---
name: power-platform-solution-packager
description: >
  Use when the user asks to "export a solution", "import a solution",
  "pack a solution", "unpack a solution", "manage ALM", or "solution management".
  Handles the full Dataverse solution lifecycle: export, unpack, pack, import.
version: 1.0.0
author: Marc
tags:
  - power-platform
  - solution
  - alm
  - pac-cli
  - devops
---

# Solution Packager (Export / Unpack / Pack / Import)

> **Trigger**: "Export the solution" or "Set up ALM for [solution]"

Manage the Dataverse solution lifecycle using PAC CLI. This covers exporting
solutions from environments, unpacking for source control, packing for
deployment, and importing into target environments.

## Prerequisites

- PAC CLI authenticated to source and target environments.
- Solution exists in the source environment.

## Step-by-Step Procedure

### Phase 1: List Available Solutions

```powershell
pac solution list
```

Identify the solution by unique name.

### Phase 2: Export Solution

```powershell
# Export unmanaged (for development)
pac solution export --name "MySolution" --path "./solutions/MySolution.zip"

# Export managed (for deployment to production)
pac solution export --name "MySolution" --path "./solutions/MySolution_managed.zip" --managed
```

### Phase 3: Unpack for Source Control

```powershell
# Unpack to a folder structure
pac solution unpack --zipfile "./solutions/MySolution.zip" --folder "./solutions/MySolution" --processCanvasApps
```

This creates a folder structure with:
- `solution.xml` -- Solution manifest
- `Entities/` -- Table definitions
- `Workflows/` -- Cloud flows
- `CanvasApps/` -- Canvas app source files
- `WebResources/` -- JavaScript, CSS, HTML files

### Phase 4: Source Control

```powershell
git add solutions/MySolution/
git commit -m "Export MySolution v1.0.0"
```

### Phase 5: Pack Solution

```powershell
# Pack from folder to zip
pac solution pack --folder "./solutions/MySolution" --zipfile "./solutions/MySolution_packed.zip"

# Pack as managed
pac solution pack --folder "./solutions/MySolution" --zipfile "./solutions/MySolution_managed.zip" --type Managed
```

### Phase 6: Import to Target Environment

```powershell
# Switch to target environment auth
pac auth select --index <target-auth-index>

# Import
pac solution import --path "./solutions/MySolution_managed.zip" --publish-changes

# Verify
pac solution list
```

### Phase 7: Version Management

Update the solution version before export:

```powershell
pac solution version --solutionPath "./solutions/MySolution" --strategy manifest --value "1.1.0"
```

## Managed vs Unmanaged

| Aspect | Unmanaged | Managed |
|---|---|---|
| Purpose | Development | Production deployment |
| Editable in target | Yes | No (locked) |
| Can be deleted | Components remain | Clean removal |
| Export command | `pac solution export` | `pac solution export --managed` |
| Pack command | `pac solution pack` | `pac solution pack --type Managed` |

## Common Mistakes & Warnings

- **Never import unmanaged to production** -- Always use managed solutions for
  non-dev environments.
- **Export before making changes** -- Always export the current state before
  modifying components.
- **`--processCanvasApps` on unpack** -- Without this flag, canvas apps are left
  as opaque zip files.
- **Auth index matters** -- `pac auth select --index N` switches the target
  environment. Verify with `pac auth who` before import.
- **Publish after import** -- Use `--publish-changes` flag or run
  `pac solution publish` separately.
- **Solution dependencies** -- If import fails with dependency errors, ensure
  prerequisite solutions are imported first.
