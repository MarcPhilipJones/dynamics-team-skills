---
name: azure-translator-managed-identity-auth
description: >
  Use when the user asks to "set up authentication for Translator", "fix real-time
  translation", "translation provider setup error", "Translator API key disabled",
  "keyless Azure Translator", "SFI broke translation", or "Entra ID auth for Cognitive
  Services from a client-side app". Rebuilds a broken key-based Azure Translator
  integration (e.g. Omnichannel/CCaaS real-time translation) as an SFI-durable
  Azure Function + Managed Identity proxy that authenticates to Translator with
  Microsoft Entra ID — no key in the browser.
version: 1.3.0
author: Marc Jones / UK Dynamics SE team
tags:
  - azure
  - translator
  - managed-identity
  - entra-id
  - sfi
  - security
---

# Set up Entra ID authentication for Azure Translator (Managed-Identity proxy)

> **Trigger**: "Set up authentication for Translator" / "real-time translation
> provider error" / "our Translator key was disabled by SFI".

Client-side apps (Omnichannel/CCaaS real-time translation web resources, Power Pages
scripts, canvas apps) traditionally call Azure Translator with an **embedded
`Ocp-Apim-Subscription-Key`**. Microsoft's **Secure Future Initiative (SFI)** disables
local/key auth on Cognitive Services resources, so those embedded keys stop working and
you get errors like *"There's something wrong with your translation provider setup."*
You **cannot** safely put a key **or** an Entra token in client-side code. The durable,
Microsoft-recommended fix (MS Q&A 5926404) is a **backend broker**: an **Azure Function
with a Managed Identity** that authenticates to Translator via Entra ID, exposed as an
intermediary endpoint the client calls.

## 🔒 Security warnings (read first)

- **Never embed a Translator subscription key in client-side code.** It's a
  high-privilege secret visible to anyone with browser dev tools. SFI will disable it
  anyway.
- **Never embed an Entra token or client secret client-side either.** Tokens leak and
  can't be scoped tightly enough. Keyless is **only** achievable via a backend proxy.
- The **only** secret the client holds is a **low-privilege, rotatable Azure Function
  key** guarding the proxy endpoint (translate-only). Treat it as a shared secret, not a
  Translator credential. Harden later with Easy Auth / Entra on the Function if the
  customer requires zero client-side secrets.
- The Function authenticates to Translator with its **system-assigned managed
  identity** + the **Cognitive Services User** RBAC role — no keys stored anywhere.
- Restrict the Function's **CORS** to the exact calling origin (the Dynamics org URL),
  not `*`.
- If you re-enable storage `publicNetworkAccess` / `allowSharedKeyAccess` to make the
  Function deploy work in an SFI tenant, that is a **demo/dev concession** — tag the
  resource `SecurityControl=Ignore` and note it; do not do this in production without
  a security review.

## The pattern — a *transparent* proxy (keeps the client change tiny)

Design the Function to **forward the same query string and body** the client already
builds, and **return Translator's raw response verbatim**. Then the client change is
just: swap the base URL and drop the key header — **all response-parsing stays
identical**.

```
Client (web resource)                Azure Function                 Azure Translator
POST /translate?api-version=3.0&to=X  -->  forwards query+body  -->  CUSTOM-DOMAIN endpoint
body: [{ "Text": "..." }]                  adds Entra Bearer          https://<subdomain>
+ function key (?code= or header)          token                     .cognitiveservices.azure.com
        <-------- raw v3 JSON response <----------------------------  RBAC: Cognitive Services User
```

> **VERIFIED (Jul 2026):** use the **custom-domain endpoint**
> (`https://<subdomain>.cognitiveservices.azure.com/translator/text/v3.0/translate`)
> with **only** the `Authorization: Bearer` header. The **global endpoint**
> (`api.cognitive.microsofttranslator.com`) + `Ocp-Apim-ResourceId` header returned
> **401001** even with a perfectly valid MI token — the custom-domain path is the
> reliable one. See gotchas below.

## Quickstart (copy-paste)

The skill ships runnable assets under `assets/` — you don't have to hand-build anything.

```powershell
# 0. One-time: install Core Tools (keyless deploy needs it)
winget install Microsoft.Azure.FunctionsCoreTools        # then restart the shell

# 1. Sign in to the TARGET tenant (never corp for demos)
az login --tenant <tenant-id> --allow-no-subscriptions

# 2. Provision everything end-to-end (creates app + MI + RBAC + identity storage +
#    keyless deploy + live verify). Run from the skill's assets/ folder.
./provision.ps1 -Subscription <subId> -Rg <rg> -FunctionApp <app> -Storage <sa> `
  -Region <region> -TranslatorName <translator> -TranslatorRg <translatorRg> `
  -ClientOrigin https://<org>.crm4.dynamics.com -ProjectDir ./function

# 3. Grab the function key for the client (the only client-side secret)
az functionapp keys list -g <rg> -n <app> --query functionKeys.default -o tsv
```

Then do the **client edit** (Phase 4) to point the web resource at
`https://<app>.azurewebsites.net/api/translate?...&code=<key>`.
The manual step-by-step below explains what `provision.ps1` does and why.

### Tested with (Jul 2026)
- Azure CLI **2.83** · Azure Functions Core Tools **4.12.1** · Node **20** (Flex Consumption FC1)
- `@azure/functions` **^4.5** · `@azure/identity` **^4.4** · Azure Translator **S1 (global, custom subdomain)**

### Bundled assets (`assets/`)
- `function/` — the complete proxy (`src/functions/translate.js`, `host.json`, `package.json`, `.funcignore`).
- `provision.ps1` — one-shot, idempotent end-to-end setup + keyless deploy + verify.
  **Clean-room validated (Jul 2026):** proven from an empty resource group through to a live
  `Bonjour → Hello`, then torn down. It checks `$LASTEXITCODE` after each create and retries on
  Azure eventual-consistency, so failures are loud, not silent.
- `teardown.ps1` — removes the app + its RBAC (keeps the Translator).
- `deploy-webresource.ps1` — (Omnichannel only) repoints the OC translation web resource at
  the proxy: blanks the old embedded key, injects the function key at deploy time (never in
  git), backs up + validates + scoped-publishes. Idempotent (re-run to rotate the key).

## Prerequisites

- Azure Translator (TextTranslation) resource **with a custom subdomain**
  (`customSubDomainName` set — required for token auth). A `global` resource works.
- Rights to create an Azure Function + assign RBAC (Owner/Contributor + User Access
  Administrator, or Owner) on the demo subscription.
- Node 20 available on the Function (Flex Consumption).
- **Azure Functions Core Tools v4 — REQUIRED for the keyless, SFI-compliant deploy.**
  Install with `winget install Microsoft.Azure.FunctionsCoreTools` (avoids the corp npm
  quarantine; restart the shell afterwards so `func` is on PATH). Without it you can only
  deploy via the Kudu `config-zip` path, which needs storage shared-key access enabled —
  i.e. you'd have to un-harden the storage to deploy. **Install Core Tools to stay
  fully compliant.**

## Step-by-step

### Phase 1 — Translator: confirm subdomain + assign RBAC
1. Confirm the Translator has a custom subdomain:
   `az cognitiveservices account show -n <tr> -g <rg> --query "properties.customSubDomainName"`.
   If null, set one (`--custom-domain <name>`). **Leave `disableLocalAuth` as-is** —
   the MI path works whether local auth is on or off, and flipping it can break other
   key-based consumers.
2. Assign the (soon-to-exist) Function MI the **Cognitive Services User** role on the
   Translator scope (do this after Phase 2 once you have the principalId).

### Phase 2 — Function app (Flex Consumption, system MI)
1. Create a Node 20 Flex Consumption app with a system-assigned identity:
   ```
   az functionapp create -g <rg> -n <app> --storage-account <sa> \
     --flexconsumption-location <region> --runtime node --runtime-version 20 \
     --assign-identity '[system]'
   ```
2. Assign RBAC to the returned `identity.principalId`:
   ```
   az role assignment create --assignee-object-id <principalId> \
     --assignee-principal-type ServicePrincipal --role "Cognitive Services User" \
     --scope <translator-resource-id>
   ```
3. App settings — **no secrets**:
   - `TRANSLATOR_ENDPOINT = https://<subdomain>.cognitiveservices.azure.com/translator/text/v3.0`
     (the code appends `/translate`). **Use the custom-domain endpoint** — see the
     401001 gotcha below.
   - `TRANSLATOR_RESOURCE_ID = /subscriptions/.../accounts/<tr>/` (only needed if you
     fall back to the global endpoint; harmless on the custom-domain path).
   - (optional) `TRANSLATOR_REGION` — omit for the custom-domain path / a `global` resource.
4. CORS — allow only the client origin:
   `az functionapp cors add -g <rg> -n <app> --allowed-origins https://<org>.crm4.dynamics.com`

### Phase 3 — Function code (transparent proxy)
- HTTP trigger, `authLevel: 'function'`. Acquire a token with `DefaultAzureCredential`
  for scope `https://cognitiveservices.azure.com/.default` (cache it — valid ~10 min).
  In a Function the MI token's `aud` = `https://cognitiveservices.azure.com` and `oid` =
  the app's `identity.principalId` (verify these if you hit 401 — add a `?debug=1`
  branch that decodes the JWT payload).
- Forward `request.query` (strip your own `code`/`debug` params) + `request.text()` to
  `${TRANSLATOR_ENDPOINT}/translate?<qs>` with headers `Authorization: Bearer <token>`,
  `Content-Type: application/json`. Return the upstream body verbatim.
- **Deploy with the keyless one-deploy** (works with hardened, shared-key-off storage):
  `func azure functionapp publish <app> --javascript --build remote` (run from the project
  folder). See "Hardening the Function's own storage" for why `config-zip` is not used on a
  hardened account. (Before hardening, `az functionapp deployment source config-zip --src
  pkg.zip --build-remote true` also works; the zip needs `host.json` + `package.json` at the root.)

### Phase 4 — Client edit (minimal)
- Replace the Translator base URL with the Function URL; append the function key
  (`&code=<key>`) or send `x-functions-key`. **Remove** the `Ocp-Apim-Subscription-Key`
  header. Leave query-string building and response parsing unchanged.
- **Omnichannel real-time translation:** use the bundled `assets/deploy-webresource.ps1`
  — it does exactly this transform on the OC sample web resource (blanks the old key,
  injects the function key at deploy time, backs up, validates, scoped-publishes).
- **Keep the function key out of source control.** For a Dataverse web resource the key
  must live in the (Dataverse-hosted) content, but your **deploy script** should fetch it
  live (`az functionapp keys list ... --query functionKeys.default`) and inject it at deploy
  time — never hardcode it in a git-tracked file. Make the script **idempotent** (detect an
  already-transformed resource and just refresh the key) so key rotation is a re-run.
  Back up the live content first, and **blank the old embedded Translator key** in the same
  edit.

## Common mistakes & warnings (things that actually bit us)

- **Storage `publicNetworkAccess = Disabled` (SFI default).** `functionapp create`
  fails: *"storage account has networking restrictions… will not start."* Fix (demo):
  `az storage account update -n <sa> -g <rg> --public-network-access Enabled` and tag
  `SecurityControl=Ignore`. A firewalled *existing* storage account won't work either —
  create a small dedicated one.
- **Storage `allowSharedKeyAccess = false` (SFI default).** Kudu zip deploy fails:
  *"Key based authentication is not permitted on this storage account."* Quick fix to get
  the app created: `az storage account update -n <sa> -g <rg> --allow-shared-key-access true`.
  **Don't stop there** — the durable fix that lets shared-key stay OFF is identity-based
  storage (see *"Hardening the Function's own storage"*); `provision.ps1` does this for you.
- **Storage in a different resource group** → `functionapp create --storage-account`
  needs the **full resource ID**, not just the name (or it looks in the app's RG).
- **Native `az` failures are SILENT in PowerShell (bit us in the provision script).**
  A non-zero `az` exit does **not** throw under `$ErrorActionPreference = 'Stop'`, so a failed
  `az ... create` lets the script sail on with an empty id — which then cascades (empty storage
  id → failed app create → empty MI → verify "No such host is known"). Worse, a `create` fired
  **immediately after `az group create`** can fail on eventual consistency. Fix: after each
  create, **re-query the resource id and throw if empty**, check `$LASTEXITCODE`, and **retry**
  a few seconds later. `provision.ps1` does all three (see its `Wait-For` helper).
- **401001 on the GLOBAL endpoint even with a valid token (VERIFIED bit us Jul 2026).**
  The global endpoint `api.cognitive.microsofttranslator.com` + `Authorization: Bearer` +
  `Ocp-Apim-ResourceId` returned `{"error":{"code":401001,...}}` despite a token with the
  correct `aud` (`https://cognitiveservices.azure.com`) and `oid` (the role-assigned MI),
  and RBAC confirmed present. **Fix: switch to the CUSTOM-DOMAIN endpoint**
  `https://<subdomain>.cognitiveservices.azure.com/translator/text/v3.0/translate` with
  **only** the Bearer header — that returned 200 immediately. Don't burn time assuming
  it's RBAC propagation; try the custom-domain endpoint first.
- **App-setting changes need a fresh worker.** The endpoint is read at module load
  (`process.env`). After changing `TRANSLATOR_ENDPOINT`, a warm Flex Consumption worker
  keeps the old value — `az functionapp restart` may not recycle it immediately; the
  next cold start picks it up. A `?debug=1` echo of `upstreamUrl` confirms which endpoint
  is actually in use.
- **Token scope** is `https://cognitiveservices.azure.com/.default` (not a Translator-
  specific scope). RBAC role is **Cognitive Services User**.
- **Design the proxy to be transparent.** If you reshape the request/response you'll
  have to rewrite all the client's language-detection/parsing logic. Forward + return
  verbatim = a ~2-line client change.
- **Deploy method depends on storage state.** On a **hardened** (shared-key-off) storage
  account, deploy with **Core Tools** `func azure functionapp publish --javascript --build
  remote` (keyless one-deploy). `az functionapp deployment source config-zip --build-remote`
  only works while shared-key is still enabled (unhardened). Remote build runs `npm install`
  on the platform, which also sidesteps the corp-device npm quarantine either way.
- **CORS + `authLevel: function`**: the browser preflights (JSON content-type). Rely on
  **host-level** `functionapp cors add` to answer the preflight; passing the key as
  `?code=` avoids a custom-header preflight entirely.

## Hardening the Function's own storage (SFI-durable, so it won't break overnight)

A Flex Consumption Function needs a storage account, and SFI overnight remediation
re-locks storage: it disables **shared-key access** and **public network access**. Since
the Functions runtime and Kudu deploy default to **key-based** storage connection strings,
those flips kill the app. Make the storage identity-based so shared-key can stay disabled
(the impactful, likely flip):

1. Grant the Function MI on the storage account: **Storage Blob Data Owner**,
   **Storage Queue Data Contributor**, **Storage Table Data Contributor**.
2. Runtime → identity: set `AzureWebJobsStorage__blobServiceUri`,
   `AzureWebJobsStorage__queueServiceUri`, `AzureWebJobsStorage__tableServiceUri` to
   `https://<sa>.<svc>.core.windows.net`, then **delete** the `AzureWebJobsStorage`
   connection-string setting.
3. Deployment → identity: `az functionapp deployment config set --deployment-storage-auth-type
   SystemAssignedIdentity`, then **delete** `DEPLOYMENT_STORAGE_CONNECTION_STRING`.
4. Restart, test. Then set `allow-shared-key-access false` and test again — translation
   must still work (runtime now uses the MI).

**Keyless deploy (the compliant, Microsoft-documented path):** with the deployment storage
set to `SystemAssignedIdentity` and the MI holding **Storage Blob Data Owner**, deploy with
**Azure Functions Core Tools** — one-deploy uploads the package to the container using the
managed identity, so it works with **shared-key access DISABLED**:
```
func azure functionapp publish <app> --javascript --build remote
```
- **Gotcha (verified):** run it from the project folder and pass the language flag
  (`--javascript` here) — with no `local.settings.json` present, func otherwise fails with
  *"Worker runtime cannot be 'None'"*.
- The legacy `az functionapp deployment source config-zip` (Kudu) path still trips a
  shared-key precheck (*"Key based authentication is not permitted"*) when shared-key is
  off — **don't use it for a hardened storage account.** If you truly can't install Core
  Tools, the fallback is to briefly enable shared-key only for the deploy then disable it
  again, but that momentarily un-hardens the account.

**Residual risk:** `publicNetworkAccess` must stay **Enabled** (Flex reaches storage over
the public endpoint without VNet). Keep it via the **`SecurityControl=Ignore`** tag (the
documented SFI opt-out). Full closure needs **VNet integration + a storage private
endpoint** (small monthly cost, more infra, harder to replicate) — only do it if the
customer requires zero public exposure.

> **Rule of thumb:** identity-based storage removes the *shared-key* flip (the big one) for
> free and is genuinely compliant; the *public-network* flip is best handled by the
> SecurityControl tag unless private networking is mandated.

## Cost

Effectively **≈£0 / month**: the Function runs on **Flex Consumption** (pay-per-execution;
demo/agent volume sits inside the free grant) and the storage account holds only the
deployment package + runtime state (pennies of transactions). The Translator resource is
pre-existing and its pricing is unchanged by moving to Entra ID auth. Still get cost
approval per your team's rule, but expect a rounding-error line item.

## Rotate the function key

The function key is the only client-side secret. To rotate:
```powershell
az functionapp keys set -g <rg> -n <app> --key-type functionKeys --key-name default --key-value $(New-Guid)
```
Then re-run the **client deploy** so the new key is re-injected (a good deploy script fetches
the key live and rewrites the web resource — never hardcodes it). Nothing else changes.

## Teardown

`assets/teardown.ps1` deletes the function app and removes its RBAC role assignments (and,
with `-DeleteStorage`, the storage account). It intentionally **leaves the Translator**
resource intact (usually shared/pre-existing).

## When NOT to use this / alternatives

- **Server-side caller** (a backend service, plug-in, or Logic App that can hold a managed
  identity or do the client-credentials flow) — call Translator with Entra ID **directly**;
  you don't need the proxy.
- **A first-party keyless translation option ships for your surface** — e.g. if Omnichannel
  real-time translation gains a genuinely keyless/native provider, prefer it. As of Jul 2026
  the OC sample is still key-based, so the proxy is required.
- **Zero public exposure mandated** — add VNet integration + a storage private endpoint on
  top of this (see Residual risk); the proxy pattern itself is unchanged.

## Key takeaway

> Keyless Cognitive Services from a browser is impossible directly — put an **Azure
> Function + Managed Identity** in front, make it a **transparent proxy**, and the only
> client-side secret becomes a rotatable function key. This is the SFI-durable,
> Microsoft-recommended pattern.

> **Verified in production (16 Jul 2026, MJCC2024/Omnichannel):** rebuilt the broken
> real-time translation web resource this way — the agent panel translated a live customer
> "bonjour" → "Hello" with no key in the browser. The custom-domain endpoint + Bearer-only
> was the unlock (global endpoint + `Ocp-Apim-ResourceId` gave 401001).
