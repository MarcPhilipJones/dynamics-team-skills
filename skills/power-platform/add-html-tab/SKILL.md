---
name: power-platform-add-html-tab
description: >
  Use when the user wants to "add a tab to a form", "embed an HTML page on a
  form", "show a web page / dashboard on a record", "add a web resource tab",
  "put a single-page HTML on a contact/account/case form", or replicate the
  "Usage tab" pattern. Adds a new model-driven form tab that hosts a single-page
  HTML web resource. Screenshot-driven and beginner-friendly: paste a picture of
  the form and accept recommended defaults. Works fully autonomously, even when
  there is NO existing tab to copy, on any table (contact, account, case, custom).
version: 2.0.0
author: UK Dynamics SE team
tags:
  - power-platform
  - dataverse
  - model-driven-forms
  - web-resource
  - customization
---

# Add an HTML Tab to a Model-Driven Form

> **Trigger**: "add a tab with an HTML page", "embed a web page on the form",
> "do it like the Usage tab", "add a web resource tab to <table>".

This skill adds a new **tab** to a model-driven (Dynamics 365 / Power Apps) main
form. The tab contains one **Web Resource control** that renders a **single-page
HTML web resource**. It is the same construct the out-of-the-box "Usage" /
"Energy" tabs use, but the skill is **self-contained** — it carries its own
known-good tab XML template, so it works even when there is no existing tab to
duplicate.

It does everything end to end: builds the HTML page, creates the web resource,
injects the tab into the form XML, saves the form, publishes, and verifies — with
a full backup and rollback path.

> **For users new to Dynamics 365:** you can run this by answering plain questions
> and accepting the recommended defaults — you don't need to know formxml, web
> resources, or GUIDs. Just paste a **screenshot** of the form (Step 0) and the
> agent works the rest out.

**Plain-language glossary**
- **Form** — the page you see on a record (e.g. a Contact). It has **tabs** across the top.
- **Tab** — a section of the form you click into (Summary, Details…). This skill adds one.
- **Web resource** — a file (here, one HTML page) stored in Dynamics and shown inside a tab.
- **Publish** — makes a change visible to users. The skill publishes for you.
- **Solution** — an optional package that lets a change be moved between environments.
- **Live binding** — the HTML reading the open record so the tab shows that person's real data.

**Quick troubleshooting**
- *Tab not visible?* Hard-refresh the app (Ctrl+F5); publishing takes ~a minute.
- *Wrong contact / wrong data on the page?* The live binding fell back — open the
  page with `?debug=1` to see why (id vs WebApi). See Step 1a + Common mistakes.
- *"Editing the wrong form"?* Confirm the exact form by screenshot/list first (Step 0).

> **Works on any table** — contact, account, case, or a custom table. Examples below
> use `contact`; pass the relevant table logical name and form id for others.

---

## What this skill does NOT do

| Need | Use instead |
|---|---|
| Add normal data fields/columns to a tab | maker portal form designer / `dv-metadata` |
| Build a PCF control or canvas-app embed | PCF tooling / canvas app embed |
| Create the table itself | `dv-metadata` |
| Move the change between environments as managed | `dv-solution` (export the solution this skill writes into) |

> **Related (in-repo):** to export/unpack/pack/import the solution this skill
> writes its components into, use
> [power-platform/solution-packager](../solution-packager/SKILL.md).

---

## Prerequisites — automated preflight (run first, fix friendly)

Run these checks up front and, if anything fails, show the **exact one-liner to fix
it** rather than failing mid-way:

1. **Org connection.**
   ```powershell
   pac org who      # shows the connected org; if wrong/missing: pac auth create --url <ORG_URL>
   az account get-access-token --resource <ORG_URL>/ --query expiresOn -o tsv
   ```
   `<ORG_URL>` = `https://org12345.crm4.dynamics.com` (trailing slash only on the
   `--resource`). If the token line errors → **`az login --tenant <TENANT_ID>`**.
2. **Identify the form (don't guess).** Confirm from the user's screenshot, then
   match it to a `systemform`. If unsure, **list the forms and let the user pick a
   number** — never edit by guesswork:
   ```sql
   SELECT formid, name, type, objecttypecode FROM systemform
   WHERE objecttypecode = 2 AND type = 2   -- objecttypecode 2 = contact; type 2 = Main
   ```
   (Dataverse MCP `read_query` or the Web API. For other tables, use that table's
   object type code, or filter by name.)
3. **Reuse an existing live-data web resource if one exists** (highly recommended —
   see Step 1a). Look for one already embedded on a form in this org and copy its
   context-resolution; the iframe nesting differs by host and the in-org one already works.
4. **Publisher prefix.** Web resource names are permanent and must be prefixed
   (e.g. `mj_`). Auto-detect the org's prefix from existing custom web resources /
   columns and reuse it; only ask if none is obvious.

---

## Step 0 — Intake (screenshot-first; offer recommended defaults)

You're often helping someone who isn't a Dynamics expert. Keep language plain,
give a **recommended default for every question**, and let them accept all
defaults with a single "yes". Be explicit that you'll **build the HTML page for
them** and **narrate every step**.

1. **Start with a screenshot (preferred).** "Open the form where you want the tab
   and paste a screenshot." From it you can: (a) **confirm the table + exact form
   name** and match it to a `systemform` (tables have many forms — this prevents
   editing the wrong one); (b) **read the existing tab labels and their order**, so
   you place the new tab by description ("after Usage") and translate that to the
   internal `-Position` value yourself — the user never needs internal names; and
   (c) see which fields are on the form to inform live binding (Step 1b). If they
   can't screenshot, list the forms (Prerequisites) and let them pick a number.
2. **Tab label & position.** "What should the tab be called, and where should it
   sit? End of the tab strip, start, or after/before a specific tab (e.g. after
   'Usage', before 'Related')?"
3. **The web page.** "I'll build the single-page HTML for you. Do you have content
   or a design in mind, or should I scaffold a clean starter page styled to match
   the form that you can refine later?"

   **If the user provides a screenshot / mock-up, ALWAYS ask these three before
   building:**
   - "Do you want me to do my **best match to what's currently in the system**
     (re-create the design as closely as I can to the screenshot)?"
   - "For fields shown in the mock-up that **already exist** on the record — do you
     want them **bound live** (the tab reflects the real record via the Web API /
     record context), or rendered as static visuals?"
   - "For **missing fields** (things in the mock-up with no column in Dataverse) —
     do you want me to **(a) create the columns and seed mock data so everything is
     live**, or **(b) just paint visual mock data** into the HTML (no schema
     changes)?" Note (a) pulls in `dv-metadata` to add columns and `dv-data` to
     seed values; (b) is purely cosmetic and fastest for demos.
4. **Solution — yes/no.** "Do you want the new tab + web resource added to a
   **solution** (recommended for anything you'll move between environments), or
   left in the default layer?"
5. **Demo persona (live fallback).** If the page binds live data, ask: "Who's your
   **demo persona** — the contact you'll show on stage? I'll use their record GUID
   as the live fallback so the tab always shows real data even if the record
   context can't be resolved." (A real GUID that's still queried live — never a
   fake painted persona, which hides binding failures.)
6. **Scope — fast vs solution route.** Present the trade-off and let them choose:

   | | **Fast (default layer)** | **Solution route** |
   |---|---|---|
   | Speed | Fastest, fewest steps | A few extra steps |
   | Best for | Demos, throwaway, single env | Anything promoted dev→test→prod |
   | ALM / portability | Hard to export cleanly | Packaged, exportable, repeatable |
   | Governance | Lands in default unmanaged layer | Tracked in a named solution |
   | Risk | Can be hard to move later | Cleaner long-term |

   > Recommend **Solution route** if this is real/shared work; **Fast** if it's a
   > one-off demo. If Solution route: ask for the **solution unique name** (and, if
   > it doesn't exist, the **publisher + prefix** to create it via `dv-solution`).

Echo the collected answers back before doing anything.

---

## Step 1 — Build the HTML web resource content

Create a self-contained single-page `.html` (no external CDNs that CSP might
block — inline the CSS/JS). Style it to feel native to the form (system font,
neutral palette, responsive). Save it locally (e.g.
`Customer Service/web/<name>.html`) so it is in source control and re-deployable.

### Design language — offer these as the main options

1. **Dynamics 365 Fluent 2 (recommended default)** — match the host app. Use the
   Fluent 2 design tokens so the tab looks native to model-driven Dynamics 365:
   - Font: `'Segoe UI', 'Segoe UI Web (West European)', system-ui, sans-serif`.
   - Core tokens (inline as CSS variables): brand `#0F6CBD` (hover `#115EA3`),
     neutral text `#242424`, secondary text `#616161`, divider `#E0E0E0`,
     surface `#FFFFFF`, canvas `#FAF9F8`, subtle bg `#F5F5F5`, success `#0E700E`,
     warning `#BC4B09`, danger `#C50F1F`.
   - Radius 4px on cards/controls, 8px on large surfaces; subtle elevation
     (`box-shadow: 0 1.6px 3.6px rgba(0,0,0,.13), 0 .3px .9px rgba(0,0,0,.11)`).
   - Use Fluent card patterns: white surface, 1px `#E0E0E0` border or shadow,
     12–16px padding, section headers in 600 weight.
   - Badges/pills with tinted backgrounds (e.g. PSR/VIP). Keep spacing on an 4px grid.
2. **Customer brand theme** — match the customer's palette/logo (e.g. for a
   pitch). Ask for hex colours / logo; keep Fluent 2 structure underneath.
3. **Match a supplied screenshot** — re-create a provided mock-up as closely as
   possible (can be combined with Fluent 2 for the chrome).

> Live-bound fields read the real record (see Step 1a). Anything not bound is
> rendered as agreed: visual mock data, or backed by real columns via
> `dv-metadata` + `dv-data`.

### Step 1a — Live binding to the record (HTML web resource)

An HTML web resource sits in an iframe on the form. Resolve the record context and
query with `Xrm.WebApi`. **This is the single most error-prone part — get it right
by copying the pattern below, which mirrors a proven, working in-org web resource.**

> **DO THIS FIRST: study a working reference in the SAME org.** If any HTML web
> resource already pulls live data on a form (e.g. an existing "Usage"/dashboard
> tab), download it and copy its exact context-resolution. Don't invent your own —
> the host (UCI form vs Customer Service **workspace/multisession** vs CIF) changes
> the iframe nesting, and the in-org reference already solved it.
> ```powershell
> $t = az account get-access-token --resource "$org/" --query accessToken -o tsv
> $r = Invoke-RestMethod -Headers @{Authorization="Bearer $t"} -Uri "$org/api/data/v9.2/webresourceset?`$filter=name eq '<existing_wr_name>'&`$select=content"
> [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($r.value[0].content)) | Set-Content ref.html
> ```

**Proven resolution order** (verified against a working dashboard in this org):

1. **`window.parent.Xrm.Page.data.entity.getId()`** — the immediate parent form's
   record. This is the PRIMARY source and works on standard UCI forms.
2. **URL params** `id` / `Id` / `ID` / `data` (from `PassParameters=true`).
3. **Walk ancestors** for any `Xrm.Page` (workspace/CIF nests deeper).
4. **A real demo-persona GUID fallback** — so the page still shows *live* data even
   if resolution fails. **Ask the user for their demo persona** and hardcode that
   contact's GUID here. (The working reference falls back to a real contact, NOT a
   fake/painted persona — a fake fallback hides failures and shows the wrong name.)

For data access use **`window.parent.Xrm.WebApi`** (fall back to self `Xrm.WebApi`,
then ancestors, then `window.top`).

```html
<script>
  function getContactId(){
    try{ if(window.parent&&window.parent.Xrm&&window.parent.Xrm.Page&&window.parent.Xrm.Page.data){
      var e=window.parent.Xrm.Page.data.entity.getId(); if(e) return e.replace(/[{}]/g,''); } }catch(e){}
    try{ var p=new URLSearchParams(location.search); var id=p.get('id')||p.get('Id')||p.get('ID')||p.get('data');
      if(id) return id.replace(/[{}]/g,''); }catch(e){}
    try{ var w=window,h=0; while(w&&h<12){ try{ if(w.Xrm&&w.Xrm.Page&&w.Xrm.Page.data&&w.Xrm.Page.data.entity){
      var x=w.Xrm.Page.data.entity.getId(); if(x) return x.replace(/[{}]/g,''); } }catch(e){} if(w===w.parent)break; w=w.parent; h++; } }catch(e){}
    return DEMO_PERSONA_GUID;   // ASK THE USER for this — live fallback, never a painted persona
  }
  function getWebApi(){
    try{ if(window.parent&&window.parent.Xrm&&window.parent.Xrm.WebApi) return window.parent.Xrm.WebApi; }catch(e){}
    try{ if(typeof Xrm!=='undefined'&&Xrm.WebApi) return Xrm.WebApi; }catch(e){}
    try{ var w=window,h=0; while(w&&h<12){ try{ if(w.Xrm&&w.Xrm.WebApi) return w.Xrm.WebApi; }catch(e){} if(w===w.parent)break; w=w.parent; h++; } }catch(e){}
    try{ if(window.top&&window.top.Xrm&&window.top.Xrm.WebApi) return window.top.Xrm.WebApi; }catch(e){}
    return null;
  }
  // retry while the client API initialises, then bind; auto-refresh when the record switches
  var lastId=null, tries=0;
  (function load(){ var api=getWebApi(), id=getContactId();
    if(api&&id){ if(id===lastId) return; lastId=id; tries=0;
      api.retrieveRecord('contact', id, "?$select=firstname,lastname,emailaddress1")
        .then(paint, function(e){ /* log + fallback */ }); return; }
    if(++tries<20){ setTimeout(load,250); return; } /* show last-resort state */ })();
  setInterval(function(){ var id=getContactId(); if(id&&id!==lastId) load(); }, 2500); // rebind on switch (re-run load, don't reload the iframe)
</script>
```

**Add a diagnostics panel — hidden by default, shown with `?debug=1`.** A fixed,
collapsible `<details>` that logs each resolution step + any `retrieveRecord` error.
Keep `console.log` on always (harmless) but only render the on-page panel when the
URL contains `?debug=1`, so live demos stay clean. When "the wrong contact shows",
open the page with `?debug=1` and the panel tells you instantly whether it's an
id-resolution or a WebApi problem. `Xrm.WebApi.retrieveRecord` returns **formatted
values** — read labels from `r["<attr>@OData.Community.Display.V1.FormattedValue"]`.

---

## Step 1b — Map fields, then preview the plan (before publishing)

**Field-mapping helper (for less-experienced users).** If the page binds live data,
introspect the table and show a plain table so the user decides per field without
knowing logical names:

| Screenshot field | Real column | Plan |
|---|---|---|
| Name | firstname / lastname | bind live |
| Tariff | mj_energytariff (choice) | bind live |
| Balance | (none found) | mock visual, or create column via `dv-metadata` |

Use the Dataverse MCP `describe` / `read_query` (or `EntityDefinitions`) to find the
logical names and types. Confirm the mapping before building.

**Dry-run preview (confirm before anything publishes).** Restate the plan in one
short paragraph and get a "yes":
> "I'll add tab **'<label>'** to form **'<form name>'** **<position>**, create web
> resource **<name>** (live-binding <fields>; mock <fields>), then publish to the
> **<default layer / solution X>**. Proceed?"

---

## Step 2 — Run the automation

The whole change (create/update web resource → back up form → inject tab →
publish → verify) is one PowerShell script. It is **idempotent** — re-running it
updates the web resource content and refreshes the tab rather than duplicating.

Save as `add-html-tab.ps1` and run it (the agent should narrate each phase):

```powershell
param(
  [Parameter(Mandatory)] [string]$OrgUrl,             # https://org.crm4.dynamics.com  (no trailing slash)
  [Parameter(Mandatory)] [string]$FormId,             # systemform GUID
  [Parameter(Mandatory)] [string]$TabLabel,           # e.g. "360"
  [Parameter(Mandatory)] [string]$WebResourceName,    # prefixed, e.g. mj_contact_360
  [Parameter(Mandatory)] [string]$HtmlPath,           # local .html file
  [string]$DisplayName = "",                          # web resource display name
  [string]$Position = "end",                          # end | start | after:<tabname> | before:<tabname>
  [string]$SolutionUniqueName = ""                    # optional: routes components into this solution
)

$ErrorActionPreference = "Stop"
$api = "$OrgUrl/api/data/v9.2"
if (-not $DisplayName) { $DisplayName = $TabLabel }

Write-Host "==> Acquiring Dataverse token via Az CLI..." -ForegroundColor Cyan
$token = az account get-access-token --resource "$OrgUrl/" --query accessToken -o tsv
if (-not $token) { throw "Could not get a token. Run: az login --tenant <TENANT_ID>" }
$headers = @{ Authorization = "Bearer $token"; "Content-Type" = "application/json";
  "OData-MaxVersion" = "4.0"; "OData-Version" = "4.0"; Accept = "application/json" }
if ($SolutionUniqueName) { $headers["MSCRM.SolutionUniqueName"] = $SolutionUniqueName }

# ---- 1. Read + back up the current form XML --------------------------------
Write-Host "==> Reading form $FormId and backing up its formxml..." -ForegroundColor Cyan
$form = Invoke-RestMethod -Method Get -Headers $headers -Uri "$api/systemforms($FormId)?`$select=name,formxml"
$backup = Join-Path (Split-Path $HtmlPath) ("formxml-backup-{0:yyyyMMdd-HHmmss}.xml" -f (Get-Date))
$form.formxml | Set-Content -Path $backup -Encoding UTF8
Write-Host "    Backed up to $backup" -ForegroundColor DarkGray

# ---- 2. Create or update the HTML web resource -----------------------------
Write-Host "==> Upserting web resource '$WebResourceName' (type 1 = HTML)..." -ForegroundColor Cyan
$content = [Convert]::ToBase64String([IO.File]::ReadAllBytes($HtmlPath))
$wrNameEsc = $WebResourceName -replace "'", "''"   # escape single quotes for the OData $filter
$existing = Invoke-RestMethod -Method Get -Headers $headers `
  -Uri "$api/webresourceset?`$select=webresourceid&`$filter=name eq '$wrNameEsc'"
if ($existing.value.Count -gt 0) {
  $webResourceId = $existing.value[0].webresourceid
  $body = @{ content = $content; displayname = $DisplayName } | ConvertTo-Json
  Invoke-RestMethod -Method Patch -Headers $headers -Uri "$api/webresourceset($webResourceId)" -Body $body | Out-Null
  Write-Host "    Updated existing web resource $webResourceId" -ForegroundColor DarkGray
} else {
  $body = @{ name = $WebResourceName; displayname = $DisplayName; webresourcetype = 1; content = $content } | ConvertTo-Json
  $resp = Invoke-WebRequest -Method Post -Headers $headers -Uri "$api/webresourceset" -Body $body
  $webResourceId = ($resp.Headers["OData-EntityId"] -replace '.*\(([^)]+)\).*','$1')
  Write-Host "    Created web resource $webResourceId" -ForegroundColor DarkGray
}

# ---- 3. Build the new tab XML (self-contained template) ---------------------
Write-Host "==> Building tab '$TabLabel'..." -ForegroundColor Cyan
$tabGuid = [guid]::NewGuid().ToString()
$secGuid = [guid]::NewGuid().ToString()
$cellGuid = [guid]::NewGuid().ToString()
$internal = "tab_" + (($TabLabel -replace '[^a-zA-Z0-9]','').ToLower())
if (-not ($internal -match '[a-z]')) { $internal = "tab_html$([guid]::NewGuid().ToString('N').Substring(0,6))" }
$padRows = ("<row />" * 40)
$tabXml = "<tab name=`"$internal`" id=`"$tabGuid`" IsUserDefined=`"1`" locklevel=`"0`" showlabel=`"true`" expanded=`"false`" visible=`"true`"><labels><label description=`"$TabLabel`" languagecode=`"1033`" /></labels><columns><column width=`"100%`"><sections><section name=`"${internal}_section_1`" id=`"$secGuid`" IsUserDefined=`"1`" locklevel=`"0`" showlabel=`"false`" showbar=`"false`" layout=`"varwidth`" celllabelalignment=`"Left`" celllabelposition=`"Left`" columns=`"1`" labelwidth=`"115`"><labels><label description=`"$TabLabel Section`" languagecode=`"1033`" /></labels><rows><row><cell locklevel=`"0`" id=`"{$cellGuid}`" showlabel=`"false`" rowspan=`"40`" colspan=`"1`" auto=`"true`"><labels><label description=`"$TabLabel`" languagecode=`"1033`" /></labels><control id=`"WebResource_$internal`" classid=`"{9FDF5F91-88B1-47F4-AD53-C11EFC01A01D}`"><parameters><Url>$WebResourceName</Url><PassParameters>true</PassParameters><Security>false</Security><Scrolling>auto</Scrolling><Border>false</Border><WebResourceId>{$webResourceId}</WebResourceId></parameters></control><events><event name=`"onload`" application=`"false`" active=`"false`" /></events></cell></row>$padRows</rows></section></sections></column></columns></tab>"

# ---- 4. Inject the tab into <tabs> at the chosen position -------------------
Write-Host "==> Injecting tab at position '$Position'..." -ForegroundColor Cyan
$doc = New-Object System.Xml.XmlDocument
$doc.PreserveWhitespace = $true
$doc.LoadXml($form.formxml)
$tabsNode = $doc.SelectSingleNode("//tabs")
if (-not $tabsNode) { throw "No <tabs> node found in formxml." }
# guard against duplicate re-runs: remove any existing tab with the same label
foreach ($t in @($tabsNode.SelectNodes("tab"))) {
  $lbl = $t.SelectSingleNode("labels/label/@description")
  if ($lbl -and $lbl.Value -eq $TabLabel) { [void]$tabsNode.RemoveChild($t) }
}
$frag = $doc.CreateDocumentFragment(); $frag.InnerXml = $tabXml
$newTab = $frag.FirstChild
switch -Regex ($Position) {
  '^start$'        { [void]$tabsNode.PrependChild($newTab); break }
  '^after:(.+)$'   { $ref = $tabsNode.SelectSingleNode("tab[@name='$($Matches[1])']"); if(-not $ref){$ref=$tabsNode.LastChild}; [void]$tabsNode.InsertAfter($newTab,$ref); break }
  '^before:(.+)$'  { $ref = $tabsNode.SelectSingleNode("tab[@name='$($Matches[1])']"); if($ref){[void]$tabsNode.InsertBefore($newTab,$ref)}else{[void]$tabsNode.AppendChild($newTab)}; break }
  default          { [void]$tabsNode.AppendChild($newTab) }
}
$newFormXml = $doc.DocumentElement.OuterXml   # NB: no XML declaration — formxml must start with <form>

# ---- 5. Save the form ------------------------------------------------------
Write-Host "==> Saving form..." -ForegroundColor Cyan
$patch = @{ formxml = $newFormXml } | ConvertTo-Json
Invoke-RestMethod -Method Patch -Headers $headers -Uri "$api/systemforms($FormId)" -Body $patch | Out-Null

# ---- 6. Publish ------------------------------------------------------------
Write-Host "==> Publishing all customizations..." -ForegroundColor Cyan
Invoke-RestMethod -Method Post -Headers $headers -Uri "$api/PublishAllXml" -Body "{}" | Out-Null

# ---- 7. Verify -------------------------------------------------------------
Write-Host "==> Verifying..." -ForegroundColor Cyan
$check = Invoke-RestMethod -Method Get -Headers $headers -Uri "$api/systemforms($FormId)?`$select=formxml"
$okTab = $check.formxml -match [regex]::Escape("description=`"$TabLabel`"")
$okWr  = $check.formxml -match [regex]::Escape($webResourceId)
if ($okTab -and $okWr) {
  Write-Host "SUCCESS: tab '$TabLabel' + web resource present and published." -ForegroundColor Green
  Write-Host "Web resource id: $webResourceId" -ForegroundColor Green
} else {
  throw "Verification failed (tab=$okTab, webresource=$okWr). Restore with the backup: $backup"
}
```

Run example:
```powershell
./add-html-tab.ps1 -OrgUrl "https://org12345.crm4.dynamics.com" `
  -FormId "<systemform-guid>" -TabLabel "360" `
  -WebResourceName "mj_contact_360" -HtmlPath ".\web\contact_360.html" `
  -Position "after:tab_usage" -SolutionUniqueName "MyDemoSolution"
```

---

## Step 3 — Verify, then show the user

After publishing, **auto-verify**: re-read the form and confirm the new tab label +
the web resource id are present (the script does this and throws if not). Then:
- Give the web resource id and a one-line summary of what changed.
- Remind them to **hard-refresh** the app (Ctrl+F5) — publishes take ~a minute.
- **Offer a deep link** to a record so they can see the tab immediately, and mention
  the `?debug=1` tip if live data ever looks wrong.

---

## Rollback (plain-English undo)

Every run saves the original form to a timestamped backup next to the HTML (e.g.
`formxml-backup-YYYYMMDD-HHMMSS.xml`). **To undo everything**:
> Restore the form from that backup and publish —
> `PATCH systemforms(<formid>)` with `{ "formxml": "<contents of backup>" }`, then
> `POST PublishAllXml`. (The new web resource is harmless to leave, or delete it.)

---

## Removing or renaming the tab (companion path)

Novices often want to undo or relabel without hand-editing XML.
- **Remove:** read the formxml, delete the `<tab>` whose `labels/label/@description`
  matches the label (the main script already removes a same-label tab on re-run —
  reuse that logic), then save + `PublishAllXml`. Optionally delete the web resource.
- **Rename:** change that tab's `<label description="…">` (and section/cell labels if
  desired), save, publish. The web resource **name** can't change — only its
  display name.
- Always back up the formxml first (same as the main flow).

---

## Common mistakes & warnings

- **No XML declaration.** `formxml` must start with `<form …>`. Always write back
  `$doc.DocumentElement.OuterXml`, never `$doc.Save()` (which prepends `<?xml…?>`
  and breaks the form). The script handles this.
- **Editing the wrong form.** Tables have many forms (Main, Quick View, Card,
  Multisession, Interactive…). Always confirm the exact `formid` with the user.
- **Forgot to publish.** Both the web resource *and* the form must be published.
  The script calls `PublishAllXml`.
- **Web resource name is permanent** and must be prefixed. You cannot rename it
  later — only delete and recreate.
- **Control classid is exact:** `{9FDF5F91-88B1-47F4-AD53-C11EFC01A01D}` (the Web
  Resource / IFRAME control). A wrong classid renders nothing.
- **Unique GUIDs.** Tab, section, and cell ids must be fresh GUIDs and the tab
  `name` unique within the form. The script generates these.
- **Token resource needs a trailing slash** (`<ORG_URL>/`) and the org URL in
  `$OrgUrl` should have **no** trailing slash (the script adds `/api/data/...`).
- **Solution scope:** to route components into a solution, pass
  `-SolutionUniqueName`; the `MSCRM.SolutionUniqueName` header adds the web
  resource and the form edit to that solution. Without it, changes land in the
  default unmanaged layer (fast, but harder to promote later).
- **CSP / external scripts.** Keep the HTML self-contained; external CDN scripts
  may be blocked. Inline CSS/JS.
- **Tab height** comes from `rowspan="40"` + the 40 padding `<row />`s. Reduce/raise
  both together to shrink/grow the embedded area.
- **"Wrong contact / wrong data" on the page** is almost always the **live binding
  failing and showing fallback/mock data**, NOT a tab problem. Causes: (1) the web
  resource is nested deeper than `window.parent` (workspace/CIF) so the form's
  `Xrm.Page` isn't found; (2) `Xrm.WebApi` wasn't ready at load. Fixes (Step 1a):
  resolve id via `window.parent.Xrm.Page` → URL params → ancestor walk; use
  `window.parent.Xrm.WebApi`; retry ~5s; and **read the on-page diagnostics panel**
  (`?debug=1`) to see whether it's an id or WebApi failure. Make the last-resort
  fallback a **real demo-persona GUID queried live**, never a fake painted persona
  (a fake fallback hides the failure and shows the wrong name).
- **Copy a working in-org web resource before inventing.** If a live-data web
  resource already exists on a form in the same org, download it and reuse its exact
  context-resolution — the iframe nesting differs by host (UCI / workspace / CIF)
  and the in-org reference already solved it.

## Key takeaway

> Adding an HTML tab = create a type-1 (HTML) web resource, inject one
> `<tab>` carrying a Web Resource control (classid `{9FDF5F91-…}`) into the form's
> `<tabs>`, save `formxml` (no XML declaration), and `PublishAllXml`. Clone the
> built-in template in this skill so it works even with no existing tab — back up
> first, verify after, and choose *fast* vs *solution* scope deliberately.
