---
name: power-platform-teams-phone-cs-setup
description: >
  Provision a Microsoft Teams Calling Plan phone number for the Dynamics 365
  Customer Service / Contact Center voice channel — end to end, from
  prerequisites to the number appearing in the Copilot Service admin centre.
  Use when "Sync from Teams" finds nothing, a Teams phone number is missing
  from the Phone Numbers list, outbound calls fail with 404 / sub-code 580406,
  or you need the full resource-account + license + Entra-app provisioning
  sequence for a Teams number in Contact Center.
version: 1.0.0
author: Antonia
tags:
  - teams-phone
  - dynamics-365-contact-center
  - voice-channel
  - calling-plan
  - resource-account
  - powershell
---

# Configure Teams Phone for Dynamics 365 Customer Service

## Purpose
Provision a Microsoft Teams Calling Plan phone number for use with the Dynamics 365 Customer Service / Contact Center voice channel. This is the complete end-to-end process — from prerequisites through to the number appearing in Copilot Service admin centre.

## When to use
- A colleague has a Teams Calling Plan phone number and wants it to appear in the Dynamics 365 Copilot Service admin centre for voice workstreams
- The "Sync from Teams" button finds nothing
- A Teams phone number is not appearing in the Phone Numbers list

## Prerequisites the user must have BEFORE running
1. **Teams Administrator** or **Teams Telephony Administrator** Entra role
2. **Global Administrator** or **Application Administrator** role (for the one-time Entra app setup)
3. A **Teams Calling Plan phone number** already acquired in Teams Admin Centre
4. The **Voice channel provisioned** in Dynamics 365 Customer Service / Contact Center
5. Available **PHONESYSTEM_VIRTUALUSER** license in the tenant
6. **Emergency address** created in Teams Admin Centre (required for Calling Plan numbers)

### Additional prerequisites for OUTBOUND calling
7. **Enterprise Voice** enabled on every agent who needs to make outbound calls (`Set-CsPhoneNumberAssignment -Identity <UPN> -EnterpriseVoiceEnabled $true`)
8. **Pay-As-You-Go Calling Plan** license (Zone 1 for UK/EU) - purchased from admin.microsoft.com -> Marketplace -> All Products -> search "Microsoft Teams Calling Plan pay-as-you-go" -> assigned to the resource account
9. **Communications Credits** purchased with funds loaded (admin.microsoft.com -> Marketplace -> All Products -> Communications Credits under Add-ons) - minimum top-up is ~EUR 20
10. **Auto-recharge** enabled on Communications Credits (Billing -> Your products -> Communications Credits -> turn on auto-recharge)
11. **No conflicting calling plans** on the resource account - unassign any other calling plan that conflicts with PAYG
12. **Outbound profile** created in Copilot Service admin centre -> Productivity -> Outbound and inbound profiles (this links the phone number, queue, and capacity profile)
13. **Capacity profile** - agents must be assigned to an outbound voice capacity profile

## Information to gather before starting
| Item | Where to find it |
|------|-----------------|
| **Dynamics App ID** | Copilot Service admin centre → Channels → Phone numbers → Advanced → Teams phone system tab |
| **ACS Resource ID** | Same page as above |
| **Phone number** | Teams Admin Centre → Voice → Phone numbers (must be E.164 format e.g. `+44XXXXXXXXXX`) |
| **Tenant domain** | e.g. `<your-tenant>.onmicrosoft.com` |

## Key lessons learned

### Entra App Permission (CRITICAL)
- An Entra app registration with **`TeamsResourceAccount.Read.All`** (delegated, well-known Graph permission GUID `ea2cbd09-253c-4f69-a0e6-07383c5f07cc`) is REQUIRED for the Sync button to work
- Without this permission, Sync **silently fails** — no error shown, just finds nothing
- **`az ad app create --required-resource-accesses`** may silently fail to save permissions — always verify with `az ad app show --id <appId> --query requiredResourceAccess` afterwards
- If permissions are empty, use **Graph API PATCH** instead: `az rest --method PATCH --url "https://graph.microsoft.com/v1.0/applications/<objectId>" --body "@perms.json"`
- After setting permissions, always run `az ad app permission admin-consent --id <appId>`

### Dynamics App ID
- The **Dynamics App ID** (from Copilot Service admin centre Manage Telephony page) must be used for ALL PowerShell commands
- Do NOT use the documentation-only reference app ID `4b8f0dce-d7d5-47a3-a27c-1764b90505e2` — it is an older/doc-only value and will not match your tenant's Dynamics App ID

### Phone Number Requirements
- Only **service numbers** (CallQueueToll/AutoAttendantToll) work with Contact Center — user numbers do NOT
- Service numbers have `VoiceApplicationAssignment` capability; user numbers only have `UserAssignment`
- Existing user numbers (`UserSubscriber` type) cannot be used — you must order a new `CallQueueToll` number via `New-CsOnlineTelephoneNumberOrder`
- Use `-NumberPrefix` (without +) when ordering: e.g. `4420` for London, not `+4420`
- Orders go to `Reserved` status and must be completed with `Complete-CsOnlineTelephoneNumberOrder` before the reservation expires (~15 minutes)

### License: PHONESYSTEM_VIRTUALUSER
- This is a **free** license ("Microsoft Teams Phone Resource Account") but must be manually purchased from M365 admin centre -> Billing -> Purchase services
- It is NOT included in M5, E5, or any other bundle
- M5/E5 includes `MCOEV` (Phone System) but NOT the calling plan component — insufficient for CallingPlan number assignment
- After purchase, the license may take **minutes to hours** to propagate to Graph API `/subscribedSkus` in trial tenants
- The well-known SKU ID `440eaaa8-b3e0-484b-a8be-62870b9ba70a` cannot be used until the tenant-level provisioning completes
- If the license appears in "Your Products" but not in the Licenses page or Graph API, it hasn't actually provisioned yet
- **Workaround:** Assign it manually in admin centre -> Users -> Active users -> select user -> Licenses and apps

### Resource Account Provisioning
- Resource accounts must have **`usageLocation`** set before license assignment
- The official MS script includes a **30-second delay** between creating the resource account and running Set/Sync — respect this
- After removing and re-adding licenses, `usageLocation` may reset to null — always verify
- Wait **60 seconds** after license assignment before attempting phone number assignment

### Azure CLI / Terminal Gotchas
- `az rest` JSON body parameters: always write to a `.json` file and use `--body "@file.json"` to avoid terminal escaping issues
- Graph PowerShell SDK has a known bug with device code credentials — use `az rest` via `az login --use-device-code` as workaround
- Azure CLI installed via winget does NOT appear in VS Code terminal PATH — use full path: `C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd`
- VS Code terminals lose `Set-ExecutionPolicy -Scope Process` when recycled — always chain it with `Import-Module MicrosoftTeams`
- `Connect-MicrosoftTeams` session does not persist across terminal sessions

### Expected Behaviour
- Teams phone numbers show **blank Carrier and Country/Region** in the admin centre — this is expected (metadata lives in Teams, not Dataverse)
- After Sync, Teams numbers appear with **Telephony = "Teams"** (not "ACS")
- The number format in `Get-CsOnlineApplicationInstance` shows `tel:+44XXXXXXXXXX` (with `tel:` prefix)

## Troubleshooting: Sync from Teams finds nothing
1. **Check Entra app permissions** — `az ad app show --id <appId> --query requiredResourceAccess` must show `ea2cbd09-253c-4f69-a0e6-07383c5f07cc`. If empty, re-add via Graph API PATCH
2. **Check admin consent** — run `az ad app permission admin-consent --id <appId>` to be safe
3. **Check resource account** — `Get-CsOnlineApplicationInstance` must show PhoneNumber, ApplicationId AND AcsResourceId all populated
4. **Re-sync** — run `Sync-CsOnlineApplicationInstance` with the Dynamics App ID and ACS Resource ID
5. **Check Application ID** — must be the Dynamics App ID from Manage Telephony, not the doc-only `4b8f0dce-...` reference

## Troubleshooting: Outbound calls fail with 404 / Sub code 580406
1. **Check Enterprise Voice** — `Get-CsOnlineUser -Identity <UPN> | Select EnterpriseVoiceEnabled` must be `True` for the AGENT making the call. Enable with: `Set-CsPhoneNumberAssignment -Identity <UPN> -EnterpriseVoiceEnabled $true`
2. **Check ActivationState** — `Get-CsPhoneNumberAssignment | Where { $_.TelephoneNumber -eq '<number>' } | Select ActivationState` must be `Activated`, not `AssignmentPending`. If pending, wait 15-60 minutes
3. **Check emergency address** — the phone number must have a CivicAddressId and LocationId assigned. Assign with: `Set-CsPhoneNumberAssignment -PhoneNumber "<number>" -LocationId "<locationId>"`
4. **Check PAYG Calling Plan** — resource account must have `Microsoft_Teams_Calling_Plan_pay_as_you_go` assigned (since Nov 2025, PHONESYSTEM_VIRTUALUSER alone does NOT support outbound OBO calls)
5. **Check Communications Credits** — `MCOPSTNC` must be assigned to the resource account AND funded with a monetary balance (admin.microsoft.com -> Billing -> Your products -> Communications Credits). A zero balance will cause 580406
6. **Check conflicting plans** — unassign any other calling plan on the resource account that conflicts with PAYG
7. **Re-sync resource account** — after license changes, run `Sync-CsOnlineApplicationInstance` again
8. **Check outbound profile** — an outbound profile must exist in Copilot Service admin centre linking the number, queue, and capacity profile

## Complete license stack for resource account (inbound + outbound)
| License | Purpose | Cost |
|---------|---------|------|
| `PHONESYSTEM_VIRTUALUSER` | Phone System for resource accounts | Free |
| `Microsoft_Teams_Calling_Plan_pay_as_you_go_(country_zone_1)` | PSTN outbound via TPE/OBO | ~EUR 1.73/month or free trial |
| `MCOPSTNC` (Communications Credits) | Funded balance for PSTN call minutes | Prepaid (min ~EUR 20) |

## Complete agent requirements for outbound calling
1. **Enterprise Voice** enabled (`EnterpriseVoiceEnabled = True`)
2. Assigned to an **outbound voice capacity profile**
3. Member of the **outbound queue**
4. **Outbound profile** exists linking the number to the queue and capacity profile

## Helper script
A companion PowerShell script, `Configure-TeamsPhoneForCS.ps1`, automates the eight-step
provisioning sequence (connect → validate number → ensure Entra app → create resource
account → associate ACS → license → assign number → final sync). It takes all
environment-specific values via `Read-Host` prompts — no tenant values are hard-coded.
After it completes, finish in the admin centre with Channels → Phone numbers → Advanced →
Teams phone system → **Sync from Teams**.
