---
name: azure-conditional-access-arm-mfa
description: >
  Use when an Azure CLI command fails with a Conditional Access / MFA error,
  when deploying to App Service / Web Apps in a tenant with Entra Conditional
  Access policies, or when troubleshooting why `az login --use-device-code`
  works for some operations but not for ARM writes. Explains the difference
  between ARM control-plane writes (subject to MFA) and Kudu / SCM data-plane
  operations (not), and the auth methods that satisfy each.
version: 1.0.0
author: Marc
tags:
  - azure
  - azure-cli
  - conditional-access
  - mfa
  - arm
  - kudu
  - scm
  - app-service
---

# Azure — Conditional Access, ARM Writes, and Kudu/SCM Auth

## When to Use This Skill

You hit one of these:

- `AADSTS50158` / `AADSTS50076` — "User must use multi-factor authentication"
  on an `az` command
- `az login --use-device-code` succeeded but the next `az resource create` /
  `az webapp config appsettings set` fails
- You can deploy a ZIP package to App Service (`az webapp up`) just fine, but
  setting app settings or restarting the service via ARM fails with MFA errors
- You're scripting against a tenant with Entra Conditional Access policies that
  enforce MFA on Azure management

## The Core Distinction — ARM vs Kudu/SCM

Azure App Service (and other PaaS) is operated through **two separate planes**:

| Plane | Operations | Subject to ARM-side MFA? |
|---|---|---|
| **ARM (control plane)** | `az webapp create`, `az webapp config …`, `az resource create/update/delete`, `az deployment …`, `az role assignment …` | **Yes** — Conditional Access ARM policies apply |
| **Kudu / SCM (data plane)** | `az webapp up` (ZIP deploy), `az webapp deployment source config-zip`, calls to `https://<app>.scm.azurewebsites.net/…`, FTP/SCM publish profiles | **No** — uses SCM credentials (basic auth or build-in publish profile), distinct from ARM auth |

**Why this matters in practice**: ZIP-deploys of your latest build keep working, so the failure manifests later — when CI/CD tries to set an app setting, restart, or scale.

## Authentication Methods — What Works for ARM Writes

| Method | Command | Satisfies ARM MFA? |
|---|---|---|
| **Interactive browser** | `az login` | **Yes** — browser handles the MFA prompt |
| **Device code** | `az login --use-device-code` | **NO** — device code flow cannot complete MFA challenge for ARM |
| **Service Principal (client secret)** | `az login --service-principal -u <appId> -p <secret> -t <tenantId>` | **Yes** — SP is exempt from interactive MFA (use a Conditional Access exclusion if your tenant blocks SPs) |
| **Service Principal (certificate)** | `az login --service-principal -u <appId> -p <cert.pem> -t <tenantId>` | **Yes** — same as secret-based SP |
| **Managed Identity** | `az login --identity` (only on Azure VMs / hosted runners with MI) | **Yes** — managed identity is the canonical "no human in the loop" answer |
| **Federated Identity / Workload Identity** | `az login --federated-token …` (GitHub OIDC, Azure DevOps OIDC) | **Yes** — preferred for CI/CD in 2025+ |

## Rules of Thumb

1. **Local developer machine** → `az login` (interactive). Don't use device code unless you're on a headless box.
2. **CI/CD (GitHub Actions / Azure DevOps)** → Workload Identity / OIDC federation. Don't store SP secrets.
3. **Local automation scripts that need to run unattended** → Service Principal with a secret stored in Key Vault, or use the user's logged-in `az` session if recent.
4. **You need to debug a failing ARM call** → run `az account show` first to confirm the active token, then run the failing command with `--debug` to see the AAD response.

## Pre-Command Checklist for ARM Writes

Before any `az` command that creates/updates/deletes resources:

- [ ] `az account show` — confirm subscription and login is still valid
- [ ] Confirm auth method satisfies MFA (interactive, SP, MI, or federated — NOT device code)
- [ ] `az configure --list-defaults` — confirm resource-group/location defaults if you rely on them
- [ ] For destructive ops (delete, deallocate, etc.), confirm with the human even when auth works

## Common Error Signatures

| Error | Cause | Fix |
|---|---|---|
| `AADSTS50158: External security challenge not satisfied` | Device code flow can't satisfy CA MFA | Re-login with `az login` (interactive) or SP |
| `AADSTS50076: User must use multi-factor authentication` | Token in cache is old / pre-MFA | `az logout` then `az login` |
| `AADSTS530034: A delegated administrator was blocked by Conditional Access` | GDAP/CSP scenario — CA blocks delegated admin | Need a different auth identity, not a delegated one |
| `Forbidden (403) RBAC` on an existing resource | Auth succeeded but missing role assignment | Check `az role assignment list --assignee <upn>` |

## Useful Default Configuration

```powershell
# One-time per machine — set common defaults so you don't repeat them
az configure --defaults group=<your-rg> location=<your-region>

# Persistent defaults are stored at:
#   $env:USERPROFILE\.azure\config

# On first use in a new session, run:
az account show           # verify login
az configure --list-defaults
```

## Why Device Code Specifically Fails for ARM

Device code OAuth flow:
1. CLI requests a device code from AAD
2. User pastes the code in a browser on a separate device
3. Browser authenticates user
4. CLI polls for the token

The user's browser is **not** the device the CLI is running on, so AAD cannot enforce device-bound MFA controls (Trusted Device, Compliant Device, Hybrid Joined) on the CLI's device. Conditional Access ARM policies that require "Require multifactor authentication" combined with "Require compliant device" cannot be satisfied. The token comes back, but ARM rejects it because the assertion isn't sufficient for the policy.

**Fix**: Interactive browser login on the same device, or use a non-user identity (SP, MI, workload identity) that's exempt from device-compliance checks.

## Key Takeaway

> **ARM writes need an MFA-capable, device-aware auth method. Kudu/SCM ZIP deploys
> don't — they ride on SCM credentials. If only your ARM commands fail with MFA
> errors while your deploys still work, your auth method is the problem, not your
> permissions.**
