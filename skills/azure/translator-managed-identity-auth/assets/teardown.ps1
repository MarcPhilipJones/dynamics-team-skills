<#
.SYNOPSIS
  Tear down the Translator managed-identity proxy created by provision.ps1.
  Removes the function app, its RBAC role assignments, and (optionally) the storage account.

.NOTES
  Does NOT delete the Translator resource (it's usually pre-existing/shared).
  Run against the correct subscription/tenant. Destructive - review before running.

.EXAMPLE
  ./teardown.ps1 -Subscription <subId> -Rg MJ_AzureFunctions -FunctionApp yw-translate-proxy `
    -Storage ywtranslateproxysa -TranslatorName mjglobaltranslate -TranslatorRg MJ_Resources -DeleteStorage
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string]$Subscription,
    [Parameter(Mandatory)] [string]$Rg,
    [Parameter(Mandatory)] [string]$FunctionApp,
    [Parameter(Mandatory)] [string]$Storage,
    [Parameter(Mandatory)] [string]$TranslatorName,
    [Parameter(Mandatory)] [string]$TranslatorRg,
    [switch]$DeleteStorage
)
$ErrorActionPreference = "Stop"
az account set --subscription $Subscription | Out-Null

# Capture the MI before deleting the app, to clean up its role assignments.
$mi = az functionapp show -n $FunctionApp -g $Rg --query identity.principalId -o tsv 2>$null

if ($mi) {
    Write-Host "Removing role assignments for MI $mi..."
    $translatorId = az cognitiveservices account show -n $TranslatorName -g $TranslatorRg --query id -o tsv 2>$null
    $storageId = az storage account show -n $Storage -g $Rg --query id -o tsv 2>$null
    foreach ($scope in @($translatorId, $storageId)) {
        if ($scope) {
            az role assignment list --assignee $mi --scope $scope --query "[].id" -o tsv 2>$null |
            ForEach-Object { if ($_) { az role assignment delete --ids $_ -o none 2>$null } }
        }
    }
}

if ($PSCmdlet.ShouldProcess($FunctionApp, "Delete function app")) {
    az functionapp delete -n $FunctionApp -g $Rg -o none
    Write-Host "Deleted function app $FunctionApp"
}

if ($DeleteStorage -and $PSCmdlet.ShouldProcess($Storage, "Delete storage account")) {
    az storage account delete -n $Storage -g $Rg --yes -o none
    Write-Host "Deleted storage account $Storage"
}

Write-Host "Teardown complete. Translator '$TranslatorName' left intact."
