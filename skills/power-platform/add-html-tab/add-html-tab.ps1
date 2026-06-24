#requires -Version 7.0
<#
  add-html-tab.ps1  —  Adds a model-driven form tab that hosts an HTML web resource.
  Part of the 'power-platform-add-html-tab' skill. Idempotent; backs up formxml first.
  Auth: Az CLI token (az login) → Dataverse Web API. Publish via PublishAllXml.
#>
param(
    [Parameter(Mandatory)] [string]$OrgUrl,             # https://org.crm4.dynamics.com (no trailing slash)
    [Parameter(Mandatory)] [string]$FormId,             # systemform GUID
    [Parameter(Mandatory)] [string]$TabLabel,           # e.g. "360"
    [Parameter(Mandatory)] [string]$WebResourceName,    # prefixed, e.g. mj_contact_360
    [Parameter(Mandatory)] [string]$HtmlPath,           # local .html file
    [string]$DisplayName = "",                          # web resource display name
    [string]$Position = "end",                          # end | start | after:<tabname> | before:<tabname>
    [string]$SolutionUniqueName = ""                    # optional: route components into this solution
)

$ErrorActionPreference = "Stop"
$api = "$OrgUrl/api/data/v9.2"
if (-not $DisplayName) { $DisplayName = $TabLabel }

Write-Host "==> Acquiring Dataverse token via Az CLI..." -ForegroundColor Cyan
$token = az account get-access-token --resource "$OrgUrl/" --query accessToken -o tsv
if (-not $token) { throw "Could not get a token. Run: az login --tenant <TENANT_ID>" }
$headers = @{ Authorization = "Bearer $token"; "Content-Type" = "application/json";
    "OData-MaxVersion" = "4.0"; "OData-Version" = "4.0"; Accept = "application/json" 
}
if ($SolutionUniqueName) { $headers["MSCRM.SolutionUniqueName"] = $SolutionUniqueName }

# ---- 1. Read + back up the current form XML --------------------------------
Write-Host "==> Reading form $FormId and backing up its formxml..." -ForegroundColor Cyan
$form = Invoke-RestMethod -Method Get -Headers $headers -Uri "$api/systemforms($FormId)?`$select=name,formxml"
$backup = Join-Path (Split-Path $HtmlPath) ("formxml-backup-{0:yyyyMMdd-HHmmss}.xml" -f (Get-Date))
$form.formxml | Set-Content -Path $backup -Encoding UTF8
Write-Host "    Form: '$($form.name)'  |  Backup: $backup" -ForegroundColor DarkGray

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
}
else {
    $body = @{ name = $WebResourceName; displayname = $DisplayName; webresourcetype = 1; content = $content } | ConvertTo-Json
    $resp = Invoke-WebRequest -Method Post -Headers $headers -Uri "$api/webresourceset" -Body $body
    $webResourceId = ($resp.Headers["OData-EntityId"] -replace '.*\(([^)]+)\).*', '$1')
    Write-Host "    Created web resource $webResourceId" -ForegroundColor DarkGray
}

# ---- 3. Build the new tab XML (self-contained template) ---------------------
Write-Host "==> Building tab '$TabLabel'..." -ForegroundColor Cyan
$tabGuid = [guid]::NewGuid().ToString()
$secGuid = [guid]::NewGuid().ToString()
$cellGuid = [guid]::NewGuid().ToString()
$internal = "tab_" + (($TabLabel -replace '[^a-zA-Z0-9]', '').ToLower())
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
foreach ($t in @($tabsNode.SelectNodes("tab"))) {
    $lbl = $t.SelectSingleNode("labels/label/@description")
    if ($lbl -and $lbl.Value -eq $TabLabel) { [void]$tabsNode.RemoveChild($t) }   # guard re-runs
}
$frag = $doc.CreateDocumentFragment(); $frag.InnerXml = $tabXml
$newTab = $frag.FirstChild
switch -Regex ($Position) {
    '^start$' { [void]$tabsNode.PrependChild($newTab); break }
    '^after:(.+)$' { $ref = $tabsNode.SelectSingleNode("tab[@name='$($Matches[1])']"); if (-not $ref) { $ref = $tabsNode.LastChild }; [void]$tabsNode.InsertAfter($newTab, $ref); break }
    '^before:(.+)$' { $ref = $tabsNode.SelectSingleNode("tab[@name='$($Matches[1])']"); if ($ref) { [void]$tabsNode.InsertBefore($newTab, $ref) }else { [void]$tabsNode.AppendChild($newTab) }; break }
    default { [void]$tabsNode.AppendChild($newTab) }
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
$okWr = $check.formxml -match [regex]::Escape($webResourceId)
if ($okTab -and $okWr) {
    Write-Host "SUCCESS: tab '$TabLabel' + web resource present and published." -ForegroundColor Green
    Write-Host "Web resource id: $webResourceId" -ForegroundColor Green
}
else {
    throw "Verification failed (tab=$okTab, webresource=$okWr). Restore from backup: $backup"
}
