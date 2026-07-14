<#
.SYNOPSIS
    Configure a Teams Calling Plan phone number for Dynamics 365 Customer Service voice channel.

.DESCRIPTION
    This script performs the complete end-to-end provisioning of a Teams phone number
    for use with Dynamics 365 Customer Service / Contact Center. It:

    1. Validates prerequisites (modules, licenses, number availability)
    2. Creates a one-time Entra app registration with TeamsResourceAccount.Read.All (if needed)
    3. Creates a Teams Resource Account linked to the Dynamics 365 application
    4. Assigns the PHONESYSTEM_VIRTUALUSER license
    5. Assigns the phone number to the resource account
    6. Syncs the resource account to Dynamics 365

    After running this script, go to Copilot Service admin centre - Channels - Phone numbers
    - Advanced - Teams phone system tab - click "Sync from Teams".

.NOTES
    Author:  Distilled from a real engagement; sanitised for sharing.
    Prereqs: Teams Administrator role, Global/Application Administrator role (first run only),
             MicrosoftTeams PowerShell module, Azure CLI (az)

    IMPORTANT: Do NOT hardcode the documentation-only app ID
    "4b8f0dce-d7d5-47a3-a27c-1764b90505e2" - always use the Dynamics App ID from your
    Copilot Service admin centre Manage Telephony page.
#>

#Requires -Modules MicrosoftTeams

[CmdletBinding()]
param()

# ============================================================================
# CONFIGURATION - Update these values for your environment
# ============================================================================

# From Copilot Service admin centre - Channels - Phone numbers - Advanced - Teams phone system tab
$DynamicsAppId    = Read-Host -Prompt "Enter the Dynamics App ID (from Manage Telephony page)"
$AcsResourceId    = Read-Host -Prompt "Enter the ACS Resource ID (from Manage Telephony page)"

# Phone number details
$PhoneNumber      = Read-Host -Prompt "Enter the phone number in E.164 format (e.g. +44XXXXXXXXXX)"
$PhoneNumberType  = Read-Host -Prompt "Enter the phone number type (CallingPlan, DirectRouting, or OperatorConnect)"

# Resource account details
$TenantDomain     = Read-Host -Prompt "Enter your tenant domain (e.g. <your-tenant>.onmicrosoft.com)"
$RaDisplayName    = Read-Host -Prompt "Enter a display name for the resource account (e.g. CS Voice 0001)"

# Strip + from number for the email prefix and generate a UPN
$numberClean = $PhoneNumber -replace '[^0-9]', ''
$RaUpn = "ra-cs-$($numberClean[-4..-1] -join '')@$TenantDomain"

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Configuration Summary" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Dynamics App ID:    $DynamicsAppId"
Write-Host "ACS Resource ID:    $AcsResourceId"
Write-Host "Phone Number:       $PhoneNumber ($PhoneNumberType)"
Write-Host "Resource Account:   $RaUpn ($RaDisplayName)"
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$confirm = Read-Host -Prompt "Proceed? (Y/N)"
if ($confirm -ne 'Y') { Write-Host "Aborted." -ForegroundColor Yellow; return }

# ============================================================================
# STEP 1: Connect to Microsoft Teams
# ============================================================================
Write-Host ""
Write-Host "[Step 1/8] Connecting to Microsoft Teams..." -ForegroundColor Yellow

try {
    $teamsCtx = Get-CsOnlineUser -ResultSize 1 -ErrorAction Stop 2>$null
    Write-Host "  Already connected to Teams." -ForegroundColor Green
} catch {
    Connect-MicrosoftTeams
    Write-Host "  Connected to Teams." -ForegroundColor Green
}

$tenantId = (Get-CsTenant).TenantId
Write-Host "  Tenant ID: $tenantId" -ForegroundColor Gray

# ============================================================================
# STEP 2: Validate phone number exists and is available
# ============================================================================
Write-Host ""
Write-Host "[Step 2/8] Validating phone number..." -ForegroundColor Yellow

$numberInfo = Get-CsPhoneNumberAssignment -NumberType $PhoneNumberType |
    Where-Object { $_.TelephoneNumber -eq $PhoneNumber }

if (-not $numberInfo) {
    Write-Host "  ERROR: Phone number $PhoneNumber not found as type $PhoneNumberType in Teams." -ForegroundColor Red
    Write-Host "  Check the number exists in Teams Admin Centre - Voice - Phone numbers." -ForegroundColor Red
    return
}

if ($numberInfo.PstnAssignmentStatus -ne 'Unassigned') {
    Write-Host "  WARNING: Number is currently assigned (Status: $($numberInfo.PstnAssignmentStatus))." -ForegroundColor Yellow
    Write-Host "  Target: $($numberInfo.AssignedPstnTargetId)" -ForegroundColor Yellow
    $continueAssigned = Read-Host -Prompt "  Continue anyway? (Y/N)"
    if ($continueAssigned -ne 'Y') { return }
}

if ($numberInfo.Capability -notcontains 'VoiceApplicationAssignment') {
    Write-Host "  ERROR: Number does not have VoiceApplicationAssignment capability." -ForegroundColor Red
    Write-Host "  Capabilities: $($numberInfo.Capability -join ', ')" -ForegroundColor Red
    Write-Host "  You may need to convert this from a User number to a Service/Voice App number" -ForegroundColor Red
    Write-Host "  in Teams Admin Centre - Voice - Phone numbers - Change usage." -ForegroundColor Red
    return
}

Write-Host "  Number found: $($numberInfo.City), $($numberInfo.IsoCountryCode) | Capabilities: $($numberInfo.Capability -join ', ')" -ForegroundColor Green

# ============================================================================
# STEP 3: Check/create Entra app with TeamsResourceAccount.Read.All (one-time)
# ============================================================================
Write-Host ""
Write-Host "[Step 3/8] Checking Entra app permission (TeamsResourceAccount.Read.All)..." -ForegroundColor Yellow

# This step uses Azure CLI - check if logged in to the right tenant
$azAccount = az account show --query tenantId -o tsv 2>$null
if ($azAccount -ne $tenantId) {
    Write-Host "  Azure CLI is not logged in to tenant $tenantId. Logging in..." -ForegroundColor Yellow
    az login --tenant $tenantId --use-device-code
}

# Check if any app already has the permission
$allApps = az rest --method GET --url "https://graph.microsoft.com/v1.0/applications" `
    --headers "Content-Type=application/json" 2>$null | ConvertFrom-Json

# TeamsResourceAccount.Read.All permission GUID (well-known Microsoft Graph value)
$teamsPermId = "ea2cbd09-253c-4f69-a0e6-07383c5f07cc"
$existingApp = $null

foreach ($app in $allApps.value) {
    foreach ($rra in $app.requiredResourceAccess) {
        foreach ($ra in $rra.resourceAccess) {
            if ($ra.id -eq $teamsPermId) {
                $existingApp = $app
                break
            }
        }
        if ($existingApp) { break }
    }
    if ($existingApp) { break }
}

if ($existingApp) {
    Write-Host "  App '$($existingApp.displayName)' already has TeamsResourceAccount.Read.All." -ForegroundColor Green
} else {
    Write-Host "  No app found with required permission. Creating one..." -ForegroundColor Yellow

    $permBody = @{
        requiredResourceAccess = @(
            @{
                resourceAppId = "00000003-0000-0000-c000-000000000000"
                resourceAccess = @(
                    @{ id = $teamsPermId; type = "Scope" }
                )
            }
        )
    } | ConvertTo-Json -Depth 5

    $permFile = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.json'
    $permBody | Set-Content -Path $permFile -Encoding UTF8

    $newApp = az ad app create --display-name "Teams Phone Sync for CS" `
        --required-resource-accesses "@$permFile" `
        --query "{appId:appId, objectId:id}" -o json 2>&1 | ConvertFrom-Json

    if ($newApp.appId) {
        az ad app permission admin-consent --id $newApp.appId 2>$null
        Write-Host "  Created app 'Teams Phone Sync for CS' ($($newApp.appId)) with admin consent." -ForegroundColor Green
    } else {
        Write-Host "  WARNING: Could not create Entra app. The Sync button may not work." -ForegroundColor Yellow
        Write-Host "  Ask a Global Admin to register an app with TeamsResourceAccount.Read.All (delegated) and grant admin consent." -ForegroundColor Yellow
    }

    Remove-Item $permFile -ErrorAction SilentlyContinue
}

# ============================================================================
# STEP 4: Create Teams Resource Account
# ============================================================================
Write-Host ""
Write-Host "[Step 4/8] Creating Teams Resource Account..." -ForegroundColor Yellow

# Check if it already exists
$existingRa = $null
try {
    $existingRa = Get-CsOnlineApplicationInstance -Identity $RaUpn -ErrorAction Stop
} catch { }

if ($existingRa) {
    Write-Host "  Resource account $RaUpn already exists (ObjectId: $($existingRa.ObjectId))." -ForegroundColor Yellow
    $raObjectId = $existingRa.ObjectId
} else {
    $newRa = New-CsOnlineApplicationInstance `
        -UserPrincipalName $RaUpn `
        -DisplayName $RaDisplayName `
        -ApplicationID $DynamicsAppId

    $raObjectId = $newRa.ObjectId
    Write-Host "  Created: $RaUpn (ObjectId: $raObjectId)" -ForegroundColor Green
}

# ============================================================================
# STEP 5: Wait for propagation, then associate ACS resource
# ============================================================================
Write-Host ""
Write-Host "[Step 5/8] Associating ACS resource (waiting 30s for propagation)..." -ForegroundColor Yellow

Start-Sleep -Seconds 30

Set-CsOnlineApplicationInstance `
    -Identity $raObjectId `
    -ApplicationId $DynamicsAppId `
    -AcsResourceId $AcsResourceId | Out-Null

Write-Host "  ACS resource associated." -ForegroundColor Green

# Sync the application instance
Sync-CsOnlineApplicationInstance `
    -ObjectId $raObjectId `
    -ApplicationId $DynamicsAppId `
    -AcsResourceId $AcsResourceId -ErrorAction Stop | Out-Null

Write-Host "  Application instance synced." -ForegroundColor Green

# ============================================================================
# STEP 6: Set usage location and assign license
# ============================================================================
Write-Host ""
Write-Host "[Step 6/8] Assigning license (PHONESYSTEM_VIRTUALUSER)..." -ForegroundColor Yellow

# Determine country from the phone number
$isoCountry = $numberInfo.IsoCountryCode
if (-not $isoCountry) { $isoCountry = "US" }

# Set usage location
$locBody = @{ usageLocation = $isoCountry } | ConvertTo-Json
$locFile = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.json'
$locBody | Set-Content -Path $locFile -Encoding UTF8

az rest --method PATCH `
    --url "https://graph.microsoft.com/v1.0/users/$raObjectId" `
    --headers "Content-Type=application/json" `
    --body "@$locFile" 2>$null

Write-Host "  Usage location set to $isoCountry." -ForegroundColor Green

# Find and assign the license
$skuResult = az rest --method GET `
    --url "https://graph.microsoft.com/v1.0/subscribedSkus" `
    --headers "Content-Type=application/json" 2>$null | ConvertFrom-Json

$virtualUserSku = $skuResult.value | Where-Object { $_.skuPartNumber -eq 'PHONESYSTEM_VIRTUALUSER' }

if (-not $virtualUserSku) {
    Write-Host "  ERROR: No PHONESYSTEM_VIRTUALUSER license found in tenant." -ForegroundColor Red
    Write-Host "  Purchase 'Microsoft Teams Phone Resource Account' licenses and re-run." -ForegroundColor Red
    Remove-Item $locFile -ErrorAction SilentlyContinue
    return
}

$available = $virtualUserSku.prepaidUnits.enabled - $virtualUserSku.consumedUnits
if ($available -le 0) {
    Write-Host "  ERROR: No available PHONESYSTEM_VIRTUALUSER licenses (all $($virtualUserSku.prepaidUnits.enabled) consumed)." -ForegroundColor Red
    Remove-Item $locFile -ErrorAction SilentlyContinue
    return
}

$licBody = @{
    addLicenses = @( @{ skuId = $virtualUserSku.skuId } )
    removeLicenses = @()
} | ConvertTo-Json -Depth 3

$licFile = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.json'
$licBody | Set-Content -Path $licFile -Encoding UTF8

$licResult = az rest --method POST `
    --url "https://graph.microsoft.com/v1.0/users/$raObjectId/assignLicense" `
    --headers "Content-Type=application/json" `
    --body "@$licFile" --query "displayName" -o tsv 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "  License assigned to $licResult." -ForegroundColor Green
} else {
    Write-Host "  ERROR assigning license: $licResult" -ForegroundColor Red
    Remove-Item $locFile, $licFile -ErrorAction SilentlyContinue
    return
}

Remove-Item $locFile, $licFile -ErrorAction SilentlyContinue

# ============================================================================
# STEP 7: Assign phone number to resource account
# ============================================================================
Write-Host ""
Write-Host "[Step 7/8] Assigning phone number to resource account..." -ForegroundColor Yellow

Set-CsPhoneNumberAssignment `
    -Identity $RaUpn `
    -PhoneNumber $PhoneNumber `
    -PhoneNumberType $PhoneNumberType

Write-Host "  Phone number assigned." -ForegroundColor Green

# Final sync after number assignment
Sync-CsOnlineApplicationInstance `
    -ObjectId $raObjectId `
    -ApplicationId $DynamicsAppId `
    -AcsResourceId $AcsResourceId -ErrorAction Stop | Out-Null

Write-Host "  Final sync completed." -ForegroundColor Green

# ============================================================================
# STEP 8: Verify and provide next steps
# ============================================================================
Write-Host ""
Write-Host "[Step 8/8] Verifying configuration..." -ForegroundColor Yellow

$finalRa = Get-CsOnlineApplicationInstance -Identity $RaUpn

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  TEAMS PHONE PROVISIONING COMPLETE" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Display Name:      $($finalRa.DisplayName)"
Write-Host "  UPN:               $($finalRa.UserPrincipalName)"
Write-Host "  Object ID:         $($finalRa.ObjectId)"
Write-Host "  Application ID:    $($finalRa.ApplicationId)"
Write-Host "  ACS Resource ID:   $($finalRa.AcsResourceId)"
Write-Host "  Phone Number:      $($finalRa.PhoneNumber)"
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "NEXT STEPS:" -ForegroundColor Cyan
Write-Host "  1. Open Copilot Service admin centre"
Write-Host "  2. Go to Channels > Phone numbers > Advanced"
Write-Host "  3. Click the 'Teams phone system' tab"
Write-Host "  4. Click 'Sync from Teams'"
Write-Host "  5. The number should appear with Telephony = 'Teams'"
Write-Host "  6. Assign the number to a voice workstream"
Write-Host ""
Write-Host "NOTE: Carrier and Country/Region will be blank for Teams numbers - this is expected." -ForegroundColor Gray
