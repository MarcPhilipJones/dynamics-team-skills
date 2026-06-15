---
name: project-manager-add-workspace
description: Add the current VS Code workspace to the Project Manager extension (alefragnani.project-manager) saved projects list, with duplicate protection and no mutation of existing entries.
---

# Project Manager Add Workspace Skill

Use this skill when the user asks to add or register the current workspace in VS Code Project Manager.

## Scope

- Target extension: `alefragnani.project-manager`
- Target file: `%APPDATA%\Code\User\globalStorage\alefragnani.project-manager\projects.json`
- Shell: PowerShell

## Required Behavior

- Ask clarification questions when any required input is missing or invalid.
- Do not auto-commit a guessed display name. The user must confirm or choose the display name before any write.
- Do not assume paths, encodings, or file shape when checks fail.
- Do not modify, reorder, or normalize existing entries.
- Do not change existing `profile` values.
- Stop without writing if a case-insensitive duplicate `rootPath` already exists.

## Execution Steps (Do Not Skip)

1. Confirm display name with the user (mandatory, before any write logic):
	- Build candidate display names from detected workspace context.
	- Present an explicit list and ask the user to choose one or provide a custom name.
	- Do not proceed until the user confirms the final display name.

2. Detect workspace identity:
   - If exactly one `*.code-workspace` file exists in the workspace root:
	 - `rootPath` = absolute path to that file
	 - default candidate name = workspace filename without extension
   - Otherwise:
	 - `rootPath` = absolute path to the workspace root folder
	 - default candidate name = workspace root folder name

3. Resolve config path in PowerShell via `$env:APPDATA`:
   - `$configPath = Join-Path $env:APPDATA 'Code\User\globalStorage\alefragnani.project-manager\projects.json'`

4. Read existing JSON as UTF-8:
   - Expected shape: array of objects with fields:
	 - `name`
	 - `rootPath`
	 - `paths` (empty array)
	 - `tags` (empty array)
	 - `enabled` (`true`)
	 - `profile` (`""`)

5. Duplicate check (case-insensitive by `rootPath`):
   - If duplicate exists: report it and stop.

6. Append new entry only when no duplicate exists:

```json
{
  "name": "<user-confirmed display name>",
  "rootPath": "<detected absolute path>",
  "paths": [],
  "tags": [],
  "enabled": true,
  "profile": ""
}
```

7. Write updated array back:
   - 2-space indentation
   - UTF-8 without BOM
   - Preserve existing entries exactly as-is

8. Confirm output:
   - Print the new entry
   - Print total project count

## PowerShell Reference Implementation

```powershell
$ErrorActionPreference = 'Stop'

# Workspace root is the current location by default.
$workspaceRoot = (Get-Location).Path

# Step 1: Detect workspace identity and build display-name candidates.
$workspaceFiles = Get-ChildItem -Path $workspaceRoot -Filter '*.code-workspace' -File
if ($workspaceFiles.Count -eq 1) {
	$detectedRootPath = $workspaceFiles[0].FullName
	$primaryCandidate = [System.IO.Path]::GetFileNameWithoutExtension($workspaceFiles[0].Name)
} else {
	$detectedRootPath = $workspaceRoot
	$primaryCandidate = Split-Path -Path $workspaceRoot -Leaf
}

$folderCandidate = Split-Path -Path $workspaceRoot -Leaf
$candidates = @($primaryCandidate, $folderCandidate) | Where-Object { $_ -and $_.Trim() } | Select-Object -Unique

Write-Output 'Choose display name for Project Manager:'
for ($i = 0; $i -lt $candidates.Count; $i++) {
	Write-Output ("[{0}] {1}" -f ($i + 1), $candidates[$i])
}
Write-Output '[C] Enter custom name'

$selection = Read-Host 'Select option number or C'
if ($selection -match '^[0-9]+$') {
	$index = [int]$selection - 1
	if ($index -lt 0 -or $index -ge $candidates.Count) {
		throw 'Invalid selection index for display name.'
	}
	$confirmedName = $candidates[$index]
} elseif ($selection.Trim().ToUpperInvariant() -eq 'C') {
	$confirmedName = Read-Host 'Enter custom display name'
	if ([string]::IsNullOrWhiteSpace($confirmedName)) {
		throw 'Custom display name cannot be empty.'
	}
} else {
	throw 'Invalid display-name selection.'
}

# Step 2: Resolve Project Manager config path.
$configPath = Join-Path $env:APPDATA 'Code\User\globalStorage\alefragnani.project-manager\projects.json'

if (-not (Test-Path -LiteralPath $configPath)) {
	throw "Project Manager config not found: $configPath"
}

# Step 3: Read JSON as UTF-8.
$raw = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
$projects = $raw | ConvertFrom-Json

if ($null -eq $projects) {
	throw 'projects.json was empty or invalid JSON.'
}

# Normalize to array semantics while preserving item objects.
$projectsArray = @($projects)

# Step 4: Duplicate check by rootPath (case-insensitive).
$duplicate = $projectsArray | Where-Object {
	$_.rootPath -and ($_.rootPath.ToString().Trim().ToLowerInvariant() -eq $detectedRootPath.Trim().ToLowerInvariant())
} | Select-Object -First 1

if ($duplicate) {
	Write-Output "Project already exists for rootPath: $($duplicate.rootPath)"
	Write-Output 'No changes made.'
	return
}

# Step 5: Append entry.
$newEntry = [ordered]@{
	name = $confirmedName
	rootPath = $detectedRootPath
	paths = @()
	tags = @()
	enabled = $true
	profile = ''
}

$updated = @($projectsArray + [pscustomobject]$newEntry)

# Step 6: Write UTF-8 (no BOM), 2-space indentation.
$json = $updated | ConvertTo-Json -Depth 10

# ConvertTo-Json uses 2-space indentation in PowerShell.
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($configPath, $json, $utf8NoBom)

# Step 7: Confirmation.
Write-Output 'Added project entry:'
$newEntry | ConvertTo-Json -Depth 5
Write-Output ("Total projects: {0}" -f $updated.Count)
```

## Clarification Prompts To Use

Ask before proceeding when any of these occur:

- `projects.json` does not exist
- JSON parse fails or top-level value is not an array
- Workspace root cannot be determined
- File access denied

Example prompt:

"I could not safely update Project Manager because `<reason>`. Do you want me to create/fix the file first, or stop here?"
