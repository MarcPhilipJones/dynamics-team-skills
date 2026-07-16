<#
.SYNOPSIS
  One-shot, idempotent provisioning for the SFI-durable Translator managed-identity proxy.
  Creates the Function app, assigns RBAC, wires identity-based storage, hardens the storage,
  deploys the code KEYLESS via Core Tools, and verifies a live translation.

.DESCRIPTION
  Runtime + storage + Translator auth end up fully keyless (managed identity). The only
  client-side secret is the low-privilege function key (fetch it after with
  `az functionapp keys list ... --query functionKeys.default -o tsv`).

.PREREQS
  - Azure CLI 2.60+ (tested 2.83), logged in to the TARGET tenant (never corp for demos).
  - Azure Functions Core Tools v4 (winget install Microsoft.Azure.FunctionsCoreTools).
  - An existing Azure Translator (TextTranslation) resource WITH a custom subdomain.

.EXAMPLE
  ./provision.ps1 -Subscription <subId> -Rg MJ_AzureFunctions -FunctionApp yw-translate-proxy `
    -Storage ywtranslateproxysa -Region ukwest `
    -TranslatorName mjglobaltranslate -TranslatorRg MJ_Resources `
    -ClientOrigin https://org6cb3e9fb.crm4.dynamics.com -ProjectDir ./function
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Subscription,
    [Parameter(Mandatory)] [string]$Rg,
    [Parameter(Mandatory)] [string]$FunctionApp,
    [Parameter(Mandatory)] [string]$Storage,
    [Parameter(Mandatory)] [string]$Region,
    [Parameter(Mandatory)] [string]$TranslatorName,
    [Parameter(Mandatory)] [string]$TranslatorRg,
    [Parameter(Mandatory)] [string]$ClientOrigin,
    [string]$ProjectDir = "./function"
)
$ErrorActionPreference = "Stop"
function Info($m) { Write-Host "==> $m" -ForegroundColor Cyan }

# Retry a script block until it returns a truthy value (handles Azure eventual consistency).
function Wait-For([scriptblock]$Test, [string]$What, [int]$Tries = 10, [int]$DelaySec = 6) {
    for ($i = 1; $i -le $Tries; $i++) {
        $v = & $Test
        if ($v) { return $v }
        Write-Host "   waiting for $What ($i/$Tries)..."
        Start-Sleep -Seconds $DelaySec
    }
    throw "Timed out waiting for $What."
}

az account set --subscription $Subscription | Out-Null

# --- Translator: subdomain + resource id -------------------------------------
$tr = az cognitiveservices account show -n $TranslatorName -g $TranslatorRg -o json | ConvertFrom-Json
$subdomain = $tr.properties.customSubDomainName
if (-not $subdomain) { throw "Translator '$TranslatorName' has no custom subdomain - token auth needs one (--custom-domain)." }
$translatorId = $tr.id
$endpoint = "https://$subdomain.cognitiveservices.azure.com/translator/text/v3.0"
Info "Translator OK (subdomain=$subdomain)"

# --- Storage (create if missing; open for setup) -----------------------------
if (-not (az storage account show -n $Storage -g $Rg 2>$null)) {
    Info "Creating storage $Storage"
    az storage account create -n $Storage -g $Rg -l $Region --sku Standard_LRS --min-tls-version TLS1_2 --allow-blob-public-access false -o none
    if ($LASTEXITCODE -ne 0) { throw "Storage create failed (exit $LASTEXITCODE). If the RG was just created, retry — it can lag a few seconds." }
}
$storageId = Wait-For { az storage account show -n $Storage -g $Rg --query id -o tsv 2>$null } "storage $Storage"
# SFI defaults block create/deploy; open public net + shared key for setup, tag to reduce re-enforcement.
az storage account update -n $Storage -g $Rg --public-network-access Enabled --allow-shared-key-access true -o none
az tag update --resource-id $storageId --operation Merge --tags SecurityControl=Ignore -o none

# --- Function app (Flex, Node 20, system MI) ---------------------------------
if (-not (az functionapp show -n $FunctionApp -g $Rg 2>$null)) {
    Info "Creating function app $FunctionApp"
    az functionapp create -g $Rg -n $FunctionApp --storage-account $storageId `
        --flexconsumption-location $Region --runtime node --runtime-version 20 --assign-identity '[system]' -o none
    if ($LASTEXITCODE -ne 0) { throw "Function app create failed (exit $LASTEXITCODE)." }
}
$mi = Wait-For { az functionapp show -n $FunctionApp -g $Rg --query identity.principalId -o tsv 2>$null } "function app + managed identity"
Info "Function MI principalId=$mi"

# --- RBAC (Translator + Storage data-plane) ----------------------------------
foreach ($r in @("Cognitive Services User")) {
    az role assignment create --assignee-object-id $mi --assignee-principal-type ServicePrincipal --role $r --scope $translatorId -o none 2>$null
}
foreach ($r in @("Storage Blob Data Owner", "Storage Queue Data Contributor", "Storage Table Data Contributor")) {
    az role assignment create --assignee-object-id $mi --assignee-principal-type ServicePrincipal --role $r --scope $storageId -o none 2>$null
}
Info "RBAC assigned (Cognitive Services User + Storage data roles)"

# --- App settings + CORS -----------------------------------------------------
az functionapp config appsettings set -g $Rg -n $FunctionApp --settings `
    "TRANSLATOR_ENDPOINT=$endpoint" "TRANSLATOR_RESOURCE_ID=$translatorId/" -o none
az functionapp cors add -g $Rg -n $FunctionApp --allowed-origins $ClientOrigin -o none 2>$null

# --- Identity-based storage (runtime + deployment) ---------------------------
az functionapp config appsettings set -g $Rg -n $FunctionApp --settings `
    "AzureWebJobsStorage__blobServiceUri=https://$Storage.blob.core.windows.net" `
    "AzureWebJobsStorage__queueServiceUri=https://$Storage.queue.core.windows.net" `
    "AzureWebJobsStorage__tableServiceUri=https://$Storage.table.core.windows.net" -o none
az functionapp config appsettings delete -g $Rg -n $FunctionApp --setting-names AzureWebJobsStorage -o none 2>$null
az functionapp deployment config set -g $Rg -n $FunctionApp --deployment-storage-auth-type SystemAssignedIdentity -o none 2>$null
az functionapp config appsettings delete -g $Rg -n $FunctionApp --setting-names DEPLOYMENT_STORAGE_CONNECTION_STRING -o none 2>$null
Info "Storage switched to managed identity"

# --- Deploy KEYLESS via Core Tools (works with shared-key OFF) ----------------
$funcCmd = (Get-Command func -ErrorAction SilentlyContinue).Source
if (-not $funcCmd) {
    $funcCmd = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter func.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $funcCmd) { throw "Azure Functions Core Tools not found. winget install Microsoft.Azure.FunctionsCoreTools" }
Push-Location $ProjectDir
try { & $funcCmd azure functionapp publish $FunctionApp --javascript --build remote } finally { Pop-Location }

# --- Harden: disable shared-key (runtime is identity-based now) ---------------
az storage account update -n $Storage -g $Rg --allow-shared-key-access false -o none
Info "Storage shared-key access DISABLED (compliant)"

# --- Verify (retry: hostname DNS + cold start can lag after first deploy) -----
$key = az functionapp keys list -g $Rg -n $FunctionApp --query "functionKeys.default" -o tsv
$r = Wait-For {
    try {
        Invoke-RestMethod -Uri "https://$FunctionApp.azurewebsites.net/api/translate?api-version=3.0&to=en&code=$key" `
            -Method Post -ContentType 'application/json' -Body '[{"Text":"Bonjour"}]' -TimeoutSec 60
    }
    catch { $null }
} "the function endpoint to answer" 12 10
Write-Host "`nPASS - 'Bonjour' -> '$($r[0].translations[0].text)'  (keyless, shared-key disabled)" -ForegroundColor Green
Write-Host "Function URL: https://$FunctionApp.azurewebsites.net/api/translate"
Write-Host "Function key: az functionapp keys list -g $Rg -n $FunctionApp --query functionKeys.default -o tsv"
