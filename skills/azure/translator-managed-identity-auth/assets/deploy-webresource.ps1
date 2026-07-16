<#
.SYNOPSIS
  Repoint an Omnichannel real-time translation web resource (the standard Microsoft
  sample, `C1WebResourceNamespace` with an embedded `bingTranslateApiClientSecret`) at
  the SFI-durable Azure Function proxy created by provision.ps1 - so no Translator key
  lives in the agent's browser.

.DESCRIPTION
  SECURITY: no secret is stored in this repo. The Azure Function KEY is fetched live at
  deploy time and injected only into the Dataverse web-resource content (the one place a
  client-side secret must live). The old embedded Translator key is BLANKED. A pre-change
  backup of the live content is written to TEMP (never committed).

  Idempotent: re-run any time (e.g. after rotating the function key - it just refreshes the key).

.PREREQS
  - `az login` to the tenant hosting BOTH the Dataverse org and the Function.
  - The web resource must be the Microsoft OC translation sample (uses
    `C1WebResourceNamespace` + `bingTranslateApiClientSecret` + the v3 `translate` URL builders).

.EXAMPLE
  ./deploy-webresource.ps1 -Org https://myorg.crm4.dynamics.com `
    -WrId <web-resource-guid> -FuncRg <rg> -FuncName <app> `
    -FuncUrl https://<app>.azurewebsites.net/api/translate
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Org,
    [Parameter(Mandatory)] [string]$WrId,
    [Parameter(Mandatory)] [string]$FuncRg,
    [Parameter(Mandatory)] [string]$FuncName,
    [Parameter(Mandatory)] [string]$FuncUrl
)
$ErrorActionPreference = "Stop"

if (-not (az account show -o json 2>$null)) { throw "Not signed in. Run: az login" }

# --- 1. Dataverse token + fetch current web-resource content -----------------
$tok = az account get-access-token --resource "$Org/" --query accessToken -o tsv
$h = @{ Authorization = "Bearer $tok"; Accept = "application/json" }
$wr = Invoke-RestMethod -Uri "$Org/api/data/v9.2/webresourceset($WrId)?`$select=name,content" -Headers $h
$js = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($wr.content))
Write-Host "Fetched $($wr.name) ($($js.Length) chars)"

# --- 2. Backup live content to TEMP (never committed) ------------------------
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backup = Join-Path $env:TEMP "wr-translate-backup-$stamp.js"
$js | Set-Content $backup -Encoding UTF8
Write-Host "Backup written: $backup"

# --- 3. Fetch the function key (secret stays out of the repo) -----------------
$key = az functionapp keys list -g $FuncRg -n $FuncName --query "functionKeys.default" -o tsv
if (-not $key) { throw "Could not retrieve function key for $FuncName." }
$proxyCodeVal = "&code=$key"

# --- 4. Transform (or refresh the key if already transformed) ----------------
if ($js -match "translateProxyUrl") {
    Write-Host "Already transformed - refreshing the function key only."
    $js = [regex]::Replace($js, "translateProxyCode:\s*'[^']*'", "translateProxyCode: '$proxyCodeVal'")
}
else {
    # 4a. Blank the old embedded Translator key + add proxy fields
    $js = [regex]::Replace($js,
        "bingTranslateApiClientSecret:\s*'[^']*',",
        "bingTranslateApiClientSecret: '',`r`n`ttranslateProxyUrl: '$FuncUrl',`r`n`ttranslateProxyCode: '$proxyCodeVal',",
        1)

    # 4b. Swap both Translator URL builders to the proxy + append the function key
    $js = $js.Replace(
        '"https://api.cognitive.microsofttranslator.com/translate?api-version=3.0&to=" + destLang;',
        'C1WebResourceNamespace.translateProxyUrl + "?api-version=3.0&to=" + destLang + C1WebResourceNamespace.translateProxyCode;')
    $js = $js.Replace(
        '"https://api.cognitive.microsofttranslator.com/translate?api-version=3.0&from=" + sourceLang + "&to=" + destLang;',
        'C1WebResourceNamespace.translateProxyUrl + "?api-version=3.0&from=" + sourceLang + "&to=" + destLang + C1WebResourceNamespace.translateProxyCode;')

    # 4c. Remove the Ocp-Apim-Subscription-Key header (the proxy handles auth now)
    $js = [regex]::Replace($js,
        ",\s*'Ocp-Apim-Subscription-Key':\s*C1WebResourceNamespace\.bingTranslateApiClientSecret",
        "")
}

# --- 5. Validate the transform BEFORE pushing --------------------------------
if ($js -match "Ocp-Apim-Subscription-Key") { throw "Transform failed: Ocp-Apim-Subscription-Key header still present." }
if ($js -notmatch "translateProxyUrl") { throw "Transform failed: translateProxyUrl not present." }
if ($js -match "api\.cognitive\.microsofttranslator\.com/translate") { throw "Transform failed: direct Translator URL still present." }

# --- 6. Push content + publish (scoped to this web resource) -----------------
$b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($js))
$body = @{ content = $b64 } | ConvertTo-Json
Invoke-RestMethod -Method Patch -Uri "$Org/api/data/v9.2/webresourceset($WrId)" `
    -Headers ($h + @{ "Content-Type" = "application/json" }) -Body $body | Out-Null
$pub = "<importexportxml><webresources><webresource>{$WrId}</webresource></webresources></importexportxml>"
$pubBody = @{ ParameterXml = $pub } | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri "$Org/api/data/v9.2/PublishXml" `
    -Headers ($h + @{ "Content-Type" = "application/json" }) -Body $pubBody | Out-Null

Write-Host "Deployed + published web resource -> $FuncUrl (key injected, old Translator key blanked)."
Write-Host "Rollback if needed: re-PATCH webresourceset($WrId) content from $backup."
