---
name: omnichannel-custom-chat-widget
description: >
  Build and configure a custom React-based Omnichannel live chat widget for
  Power Pages Code Sites (v2 data model) using @microsoft/omnichannel-chat-sdk.
  Covers: Vite bundler setup (ACS adapter stub), SDK initialization, authenticated
  chat via self-signed JWTs (custom-portal approach — Code Sites do NOT support
  /_services/auth/token or /publickey), pre-chat forms, custom UI, error
  boundaries, RSA key pair generation, jose library JWT signing, and Dataverse
  auth-settings configuration via PowerShell.
  Use when: adding live chat, fixing "visitor" identity, customizing chat UI,
  rendering knowledge-article citations as clickable links, or troubleshooting
  Omnichannel SDK on Code Sites with Vite.
version: 3.2.0
author: Marc
applyTo: "powerpages.config.json,**/powerpages.config.json"
tags:
  - power-pages
  - omnichannel
  - chat-widget
  - live-chat
  - customer-service
  - authenticated-chat
  - vite
  - react
  - code-sites
---

# Custom Omnichannel Chat Widget for Power Pages Code Sites

> **Trigger**: "add live chat", "chat widget", "omnichannel chat", "custom chat",
> "visitor instead of user name", "chat not authenticating", "agent sees visitor",
> "SDK chat", "Vite omnichannel", "chat widget authentication"

Build a fully custom React chat widget using the lightweight
`@microsoft/omnichannel-chat-sdk` for Power Pages Code Sites (v2 data model)
with Vite. This replaces the default Microsoft chat widget with a branded,
customizable experience while preserving authenticated chat so agents see the
real user identity.

> **Why bundle the SDK instead of the OOB LiveChatWidget bootstrapper?**
> The code-site CSP restricts `script-src` to `'self'` + `content.powerapps.com`,
> so the external `oc-cdn…/LiveChatBootstrapper.js` is **blocked** (and you can't
> edit a code-site's CSP). But the CSP sets **only** `script-src` and `style-src`
> — there is **no `connect-src`/`default-src`** — so runtime WebSocket/fetch to
> `*.omnichannelengagementhub.com` is **unrestricted**. Bundling the SDK (which
> runs from `'self'`) therefore works where the external script cannot. This is
> the whole reason this skill exists — see also the `embedding-advanced-widget`
> skill's Omnichannel exception.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [Step 1 — Install Dependencies](#step-1--install-dependencies)
4. [Step 2 — Vite Configuration (CRITICAL)](#step-2--vite-configuration-critical)
5. [Step 3 — Omnichannel Config Values](#step-3--omnichannel-config-values)
6. [Step 4 — Authentication (Custom-Portal JWT Approach)](#step-4--authentication-custom-portal-jwt-approach)
7. [Step 5 — Chat Widget Component](#step-5--chat-widget-component)
8. [Step 6 — App.tsx Integration](#step-6--apptsx-integration)
9. [Step 7 — Dataverse Auth Settings (PowerShell)](#step-7--dataverse-auth-settings-powershell)
10. [Step 8 — Deploy & Restart](#step-8--deploy--restart)
11. [Troubleshooting](#troubleshooting)
12. [What Does NOT Work](#what-does-not-work)
13. [Design Token Reference](#design-token-reference)
14. [Custom Context Variables (Agent Toast Notifications)](#custom-context-variables-agent-toast-notifications)
15. [End-to-End Setup Checklist](#end-to-end-setup-checklist)
16. [Knowledge-Article Citations & Copilot Studio Citation Chrome](#knowledge-article-citations--copilot-studio-citation-chrome)

---

## Architecture Overview

```
┌─────────────────────────────────────────────┐
│  React SPA (Vite)                           │
│  ┌──────────────┐  ┌────────────────────┐   │
│  │ ChatWidget   │  │ auth.ts            │   │
│  │ (custom UI)  │──│ Signs JWT with     │   │
│  └──────┬───────┘  │ jose + RSA-2048    │   │
│         │          └────────┬───────────┘   │
│         │                   │               │
│  ┌──────▼───────────────────▼───────────┐   │
│  │ @microsoft/omnichannel-chat-sdk      │   │
│  │  - OC_CONFIG (orgUrl, orgId, widget) │   │
│  │  - chatSDKConfig.getAuthToken → JWT  │   │
│  └──────────────────┬──────────────────┘    │
│                     │                       │
│  public/auth-publickey ← RSA PEM (static)   │
└─────────────────────┼───────────────────────┘
                      │ WebSocket / REST
         ┌────────────▼───────────────┐
         │ Dynamics 365 Omnichannel   │
         │ ← validates JWT with       │
         │   /auth-publickey          │
         └────────────────────────────┘
```

**Key decisions**:
- **SDK only** (`omnichannel-chat-sdk`) — NOT the full widget package
- **Custom React UI** — pre-chat form, message bubbles, typing indicator
- **Self-signed JWT auth** — RS256 signed client-side via `jose` library (custom-portal approach)
- **Lazy loaded** — `React.lazy()` + error boundary to avoid crash on failure
- **Self-hosted public key** — PEM file in `public/auth-publickey` (not `/_services/auth/publickey`)

---

## Prerequisites

- Power Pages Code Site deployed with `pac pages upload-code-site`
- Vite + React + TypeScript project (`npm create vite@latest`)
- Omnichannel for Customer Service provisioned in Dynamics 365
- Live chat workstream + chat widget created in Customer Service Admin Center
- RSA-2048 key pair generated (see Step 4a)
- `jose` npm package installed (see Step 4b)
- Azure CLI (`az`) available for Dataverse token acquisition
- User signed in to the portal (for authenticated chat)
- PowerShell 7 (`pwsh`) for Dataverse setup scripts

---

## Step 1 — Install Dependencies

```bash
npm install @microsoft/omnichannel-chat-sdk jose
```

- `@microsoft/omnichannel-chat-sdk` — Omnichannel chat SDK (lightweight, no UI)
- `jose` — JWT signing library using Web Crypto API (~8 KB gzipped)

> **Do NOT install** `@microsoft/omnichannel-chat-widget` — it is webpack-only,
> 7MB+, and requires `postcss`, `sanitize-html`, `fs`, `path`, `source-map-js`
> which break Vite. Use the SDK-only approach with custom UI.

---

## Step 2 — Vite Configuration (CRITICAL)

The SDK imports `@microsoft/botframework-webchat-adapter-azure-communication-chat`
which has a broken `package.json` entry point. Must stub it with BOTH:
- **Rollup plugin** (production build) with `enforce: 'pre'`
- **esbuild plugin** (dev server dependency pre-bundling)

Also needs `define: { global: 'globalThis' }` for Node.js `global` polyfill.

```typescript
// vite.config.ts
import { defineConfig, type Plugin } from 'vite'
import react from '@vitejs/plugin-react'

const ACS_PKG = '@microsoft/botframework-webchat-adapter-azure-communication-chat';

function stubAcsAdapter(): Plugin {
  const STUB_ID = '\0acs-adapter-stub';
  return {
    name: 'stub-acs-adapter',
    enforce: 'pre',
    resolveId(id) { if (id === ACS_PKG) return STUB_ID; },
    load(id) { if (id === STUB_ID) return 'export default {};'; },
  };
}

export default defineConfig({
  plugins: [react(), stubAcsAdapter()],
  define: { global: 'globalThis' },
  optimizeDeps: {
    esbuildOptions: {
      plugins: [{
        name: 'stub-acs-adapter-esbuild',
        setup(build) {
          build.onResolve(
            { filter: /botframework-webchat-adapter-azure-communication-chat/ },
            () => ({ path: ACS_PKG, namespace: 'acs-stub' })
          );
          build.onLoad(
            { filter: /.*/, namespace: 'acs-stub' },
            () => ({ contents: 'module.exports = {};', loader: 'js' })
          );
        },
      }],
    },
  },
});
```

### Why Both Plugins?

| Plugin | When it runs | Purpose |
|--------|-------------|---------|
| Rollup (`stubAcsAdapter`) | `vite build` | Stubs the import in production bundles |
| esbuild (`optimizeDeps`) | `vite dev` | Stubs during dependency pre-bundling |

Without both, you get `Cannot find module` or `Missing export` errors in one
mode or the other.

### Vite 8 / Rolldown note (verified Jul 2026)

On **Vite 8** (Rolldown engine) the build prints a warning that
`optimizeDeps.esbuildOptions` is deprecated in favour of
`optimizeDeps.rolldownOptions`. This is **harmless** — the Rollup `enforce: 'pre'`
`stubAcsAdapter` plugin is what makes `vite build` succeed (the esbuild block only
affects the dev pre-bundle). The build works: the SDK lands in a `lib-*.js` chunk
(~880 KB) and, if you lazy-load the widget, it becomes its own small chunk (~8 KB).

**tsc gotcha:** the esbuild `PluginBuild` type isn't resolvable from this config,
so annotate the callback param as `any` (with an eslint-disable) to satisfy
`tsc -b`:

```typescript
plugins: [{
  name: 'stub-acs-adapter-esbuild',
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  setup(build: any) { /* … */ },
}],
```

---

## Step 3 — Omnichannel Config Values

Get these from **Customer Service Admin Center → Workstreams → [your chat
workstream] → Chat widget → Widget details**:

```typescript
const OC_CONFIG = {
  orgUrl: 'https://<your-org>.omnichannelengagementhub.com',
  orgId: '<org-guid>',        // Also visible in widget snippet
  widgetId: '<widget-guid>',  // The chat widget ID
};
```

You can also extract these from the widget code snippet (the
`data-org-url`, `data-org-id`, and `data-app-id` attributes on the
bootstrapper script tag).

### Anonymous chat — demo quickstart (skip Steps 4 & 7)

Most of this skill covers **authenticated** chat (self-signed JWT) so the agent
sees the real contact. For a **demo**, anonymous chat is far simpler and enough:
the agent sees a "Visitor", and you pass the caller's name + question via
`startChat` custom context. **Skip Step 4 (JWT/RSA/jose) and Step 7 (Dataverse
auth settings) entirely** — you do NOT need `getAuthToken`.

```typescript
// Anonymous: construct the SDK with config ONLY (no chatSDKConfig).
const sdk = new OmnichannelChatSDK(OC_CONFIG);
await sdk.initialize();
await sdk.startChat({
  customContext: {
    Name:     { value: name || 'Website visitor', isDisplayable: true },
    Question: { value: question,                  isDisplayable: true },
  },
});
```

Everything else (Step 5 UI, post-greeting send, `sdk.sendMessage({ content })`
object form, error boundary) is identical. When you later need real identity,
add the Step 4/7 JWT path — no UI changes required.

---

## Step 4 — Authentication (Custom-Portal JWT Approach)

### Why Are Custom JWTs Needed on Code Sites?

> **CRITICAL DISCOVERY**: Power Pages Code Sites (v2 data model) do **NOT** expose
> the traditional `/_services/auth/token` or `/_services/auth/publickey` endpoints.
> These endpoints only exist on traditional portals created via Portal Management.
> On Code Sites, requesting these URLs returns the SPA HTML shell (200 OK with HTML),
> not a JWT or RSA public key.

The Omnichannel SDK's auth flow works like this:

1. `sdk.initialize()` → calls `getChatConfig()` → server returns `LiveChatConfigAuthSettings`
2. If `authSettings` is null → **SDK skips auth entirely** and never calls `getAuthToken()`
3. If `authSettings` is present → SDK calls `getAuthToken()` → sends JWT to OC backend
4. OC backend fetches the public key from `msdyn_publickeyurl` → validates JWT signature
5. `sub` claim in JWT maps to a Dataverse Contact record → agent sees authenticated user

Since Code Sites can't serve the built-in auth endpoints, we use the **"custom portal"**
approach documented on MS Learn: generate our own RSA key pair, host the public key
as a static file, and sign JWTs ourselves.

### Step 4a — Generate RSA-2048 Key Pair

```powershell
# Using .NET (works in PowerShell 7 without openssl)
$rsa = [System.Security.Cryptography.RSA]::Create(2048)

# Export public key (PEM format) → goes in public/ folder for deployment
$pubBytes = $rsa.ExportSubjectPublicKeyInfo()
$pubB64 = [Convert]::ToBase64String($pubBytes)
$pubPem = "-----BEGIN PUBLIC KEY-----`n"
for ($i = 0; $i -lt $pubB64.Length; $i += 64) {
  $pubPem += $pubB64.Substring($i, [Math]::Min(64, $pubB64.Length - $i)) + "`n"
}
$pubPem += "-----END PUBLIC KEY-----"
[System.IO.File]::WriteAllText("$PWD/public/auth-publickey", $pubPem)

# Export private key (PEM format) → goes in keys/ folder (NEVER commit)
New-Item -ItemType Directory -Path "./keys" -Force | Out-Null
$privBytes = $rsa.ExportPkcs8PrivateKey()
$privB64 = [Convert]::ToBase64String($privBytes)
$privPem = "-----BEGIN PRIVATE KEY-----`n"
for ($i = 0; $i -lt $privB64.Length; $i += 64) {
  $privPem += $privB64.Substring($i, [Math]::Min(64, $privB64.Length - $i)) + "`n"
}
$privPem += "-----END PRIVATE KEY-----"
[System.IO.File]::WriteAllText("$PWD/keys/oc-auth-private.pem", $privPem)
```

Alternatively, using openssl:
```bash
openssl genpkey -algorithm RSA -out keys/oc-auth-private.pem -pkeyopt rsa_keygen_bits:2048
openssl rsa -pubout -in keys/oc-auth-private.pem -out public/auth-publickey
```

**IMPORTANT**: Add `keys/` and `*.pem` to `.gitignore`!

### Step 4b — Install jose Library

```bash
npm install jose
```

The `jose` library provides RSA JWT signing that works in the browser using
the Web Crypto API. It's lightweight (~8 KB gzipped).

### Step 4c — Authentication Service (auth.ts)

The private key is imported as a raw string using Vite's `?raw` suffix.

> ⚠ **SECURITY NOTE**: The private key is bundled into the client-side JavaScript.
> This is acceptable for **dev/test environments** only. For production, move JWT
> signing to a server-side Azure Function and have the client fetch the signed JWT.

```typescript
// services/auth.ts
import { SignJWT, importPKCS8 } from 'jose';
import privateKeyPem from '../../keys/oc-auth-private.pem?raw';

const OC_JWT_ISSUER = '<your-portal>.powerappsportals.com'; // Must match portal domain
let cachedSigningKey: CryptoKey | null = null;

async function getSigningKey(): Promise<CryptoKey> {
  if (!cachedSigningKey) {
    cachedSigningKey = await importPKCS8(privateKeyPem, 'RS256');
  }
  return cachedSigningKey;
}

export async function getOmnichannelAuthToken(): Promise<string | null> {
  if (window.location.hostname === 'localhost') return null;

  const user = getPortalUser();
  if (!user?.contactId) {
    console.warn('[Auth] No portal user — cannot create OC auth token');
    return null;
  }

  try {
    const key = await getSigningKey();
    const now = Math.floor(Date.now() / 1000);
    const jwt = await new SignJWT({
      sub: user.contactId,       // Contact GUID — OC uses this to identify the user
      lwicontexts: JSON.stringify({
        portalcontactid: user.contactId,
      }),
    })
      .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
      .setIssuedAt(now)
      .setExpirationTime(now + 300)  // 5 minutes
      .setIssuer(OC_JWT_ISSUER)
      .sign(key);

    console.debug('[Auth] Created OC auth JWT for', user.displayName);
    return jwt;
  } catch (e) {
    console.error('[Auth] JWT signing failed:', e);
    return null;
  }
}
```

### JWT Claims Required by Omnichannel

| Claim | Required | Description |
|-------|----------|-------------|
| `sub` | **Yes** | Contact ID (GUID). OC uses this to auto-identify the Dataverse contact record. |
| `iss` | **Yes** | Issuer — typically the portal domain. |
| `iat` | **Yes** | Issued-at timestamp (numeric Unix time). |
| `exp` | **Yes** | Expiration timestamp. 5 minutes is recommended. |
| `lwicontexts` | No | Stringified JSON with context variables for routing/display. |

The `sub` claim is the most important — it must contain the Dataverse contact
record's GUID. This is what maps the chat to a known customer instead of "Visitor".

### How the Public Key Is Served

The file `public/auth-publickey` is a plain PEM file. Vite copies everything in
`public/` to `dist/` during build. After deploying with `pac pages upload-code-site`,
it becomes accessible at `https://<your-site>.powerappsportals.com/auth-publickey`.

The OC backend fetches this URL to validate JWT signatures. It must:
- Return HTTP 200
- Contain a valid RSA public key in PEM format
- Be accessible **before** you create the auth settings in Dataverse (Dataverse
  validates the URL during creation)

### Chicken-and-Egg: Deploy Before Creating Auth Settings

Dataverse validates `msdyn_publickeyurl` when creating the auth settings record.
If the URL returns HTML or 404, creation fails with:
```
"We couldn't validate your public key. Please make sure your key value is valid"
```

**Solution**: Deploy the site first (`pac pages upload-code-site`) so `/auth-publickey`
is accessible, then run the auth settings PowerShell script.

### Common Bug Patterns (AVOID THESE)

```typescript
// ❌ WRONG — conditional, cached, one-shot
const chatSDKConfig: Record<string, unknown> = {};
const authToken = await getOmnichannelAuthToken();
if (authToken) {
  chatSDKConfig.getAuthToken = async () => authToken;  // cached!
}
```
If `authToken` is null, `getAuthToken` is **never set** → SDK skips auth → "Visitor".

```typescript
// ❌ WRONG — relying on /_services/auth/token
const res = await fetch('/_services/auth/token');
```
This endpoint does NOT exist on Code Sites v2. It returns the SPA HTML shell.

```typescript
// ✅ CORRECT — always set, dynamic, self-signed JWT
const chatSDKConfig = {
  getAuthToken: async () => {
    const token = await getOmnichannelAuthToken();
    return token ?? '';
  },
};
const sdk = new OmnichannelChatSDK(OC_CONFIG, chatSDKConfig);
```

---

## Step 5 — Chat Widget Component

### SDK Loading Pattern

Lazy-load the SDK to keep the main bundle small (~845 KB SDK + deps):

```typescript
let sdkPromise: Promise<typeof import('@microsoft/omnichannel-chat-sdk')> | null = null;
function loadSDK() {
  if (!sdkPromise) sdkPromise = import('@microsoft/omnichannel-chat-sdk');
  return sdkPromise;
}
```

### SDK Initialization

```typescript
const initSDK = useCallback(async () => {
  if (sdkRef.current) return true;
  try {
    const mod = await loadSDK();
    const OmnichannelChatSDK =
      mod.OmnichannelChatSDK ?? (mod as any).default?.OmnichannelChatSDK;
    if (!OmnichannelChatSDK) throw new Error('OmnichannelChatSDK not found');

    // ALWAYS set getAuthToken — dynamic, fetches fresh token each call
    const chatSDKConfig = {
      getAuthToken: async () => {
        const token = await getOmnichannelAuthToken();
        return token ?? '';
      },
    };

    const sdk = new OmnichannelChatSDK(OC_CONFIG, chatSDKConfig);
    await sdk.initialize();

    // ── Debug: verify OC backend returned auth settings ──
    const sdkAny = sdk as any;
    console.debug('[ChatWidget] SDK initialized. authSettings:', sdkAny.authSettings);
    console.debug('[ChatWidget] LiveChatConfigAuthSettings:',
      JSON.stringify(sdkAny.liveChatConfig?.LiveChatConfigAuthSettings ?? null));
    if (!sdkAny.authSettings) {
      console.warn('[ChatWidget] ⚠ SDK has NO authSettings — auth will be SKIPPED.');
      console.warn('[ChatWidget] Fix: link auth settings to live chat widget in');
      console.warn('  CS Admin Center → Workstreams → Behaviors tab');
    }

    sdkRef.current = sdk;
    return true;
  } catch (e) {
    console.error('[ChatWidget] SDK init failed:', e);
    return false;
  }
}, []);
```

### Starting a Chat with Custom Context

```typescript
await sdk.startChat({
  customContext: {
    Name:             { value: formName ?? '',     isDisplayable: true },
    Email:            { value: formEmail ?? '',    isDisplayable: true },
    Question:         { value: formQuestion ?? '', isDisplayable: true },
    CustomerQuestion: { value: formQuestion ?? '', isDisplayable: true },
    ...(portalUser?.contactId ? {
      portalcontactid: { value: portalUser.contactId, isDisplayable: false },
    } : {}),
  },
});
```

### Post-Greeting Question Sending (CRITICAL PATTERN)

> **Do NOT use a blind `setTimeout` to send the pre-chat question.** The bot
> ignores messages that arrive before its greeting. You MUST wait for the first
> bot message before sending.

> **`sdk.sendMessage({ content: text })` (object) — NOT `sdk.sendMessage(text)`
> (plain string).** Plain string format is silently ignored by the bot.

```typescript
// ── In the startChat flow, BEFORE registering onNewMessage: ──
let greetingReceived = false;
let pendingQuestion: string | null = null;

// ── Inside onNewMessage handler, AFTER rendering the bot message: ──
if (!greetingReceived && pendingQuestion) {
  greetingReceived = true;
  const q = pendingQuestion;
  pendingQuestion = null;
  setTimeout(async () => {
    try {
      setMessages(prev => [...prev, {
        id: `user-prechat-q-${Date.now()}`,
        content: q,
        sender: 'user' as const,
        timestamp: new Date(),
      }]);
      await sdk.sendMessage({ content: q });  // MUST be object format!
    } catch (err) {
      console.warn(TAG, 'Post-greeting sendMessage failed:', err);
    }
  }, 1500);  // 1.5s delay after greeting for bot readiness
} else if (!greetingReceived) {
  greetingReceived = true;
}

// ── After setPhase('chat'), instead of blind setTimeout: ──
if (questionText) {
  pendingQuestion = questionText;
  // Safety fallback — send after 8s if bot never greets
  setTimeout(async () => {
    if (pendingQuestion) {
      const q = pendingQuestion;
      pendingQuestion = null;
      greetingReceived = true;
      await sdk.sendMessage({ content: q });
    }
  }, 8000);
}
```

**Flow**: Connected → Bot greeting arrives → 1.5s pause → User question appears + sent → Bot processes it

### Listening for Events

```typescript
sdk.onNewMessage((msg: any) => {
  if (msg.content) {
    setMessages(prev => [...prev, {
      id: msg.id ?? `${Date.now()}-${Math.random()}`,
      content: msg.content,
      sender: 'agent',
      timestamp: new Date(),
    }]);
  }
  setTyping(false);
});

sdk.onTypingEvent(() => setTyping(true));
sdk.onAgentEndSession(() => setPhase('ended'));
```

### Portal User Detection

`Microsoft.Dynamic365.Portal.User` provides:
- `userName` — login identifier (NOT always an email!)
- `contactId` — Dataverse contact GUID
- `firstName`, `lastName`

To get the email, fetch from the contact record:
```typescript
const res = await fetch(`/_api/contacts(${contactId})?$select=emailaddress1`);
const data = await res.json();
const email = data.emailaddress1;
```

### Message Rendering Tips

- Bot/agent messages may contain `\n` — use `white-space: pre-wrap` on bubble CSS
- For HTML content, use `dangerouslySetInnerHTML` with sanitization (DOMParser)
- Scroll to bottom on new messages with `useRef` + `scrollIntoView`

---

## Step 6 — App.tsx Integration

Wrap in error boundary + Suspense to prevent SDK failures from crashing the SPA:

```tsx
import { lazy, Suspense, Component, type ReactNode } from 'react';

const ChatWidget = lazy(() => import('./components/ChatWidget'));

class ChatErrorBoundary extends Component<
  { children: ReactNode },
  { hasError: boolean }
> {
  state = { hasError: false };
  static getDerivedStateFromError() { return { hasError: true }; }
  componentDidCatch(err: unknown) { console.error('[ChatWidget] Crashed:', err); }
  render() { return this.state.hasError ? null : this.props.children; }
}

// In your app JSX:
<ChatErrorBoundary>
  <Suspense fallback={null}>
    <ChatWidget />
  </Suspense>
</ChatErrorBoundary>
```

---

## Step 7 — Dataverse Auth Settings

For agents to see the authenticated user name (not "Visitor"), you must create
**Omnichannel authentication settings** in Dataverse and link them to the
live chat widget.

### Create via PowerShell

```powershell
$envUrl   = "https://org<id>.crm4.dynamics.com"
$token    = az account get-access-token --resource $envUrl --query accessToken -o tsv
$headers  = @{
  "Authorization"    = "Bearer $token"
  "Content-Type"     = "application/json"
  "OData-MaxVersion" = "4.0"
  "OData-Version"    = "4.0"
}

$portalUrl         = "https://<your-site>.powerappsportals.com"
$liveChatConfigId  = "<live-chat-config-guid>"   # from msdyn_livechatconfigs

# Step 1: Create authentication settings record
$authBody = @{
  msdyn_name                    = "Portal Auth Settings"
  msdyn_authenticationtype      = 192350000       # OAuth 2.0 implicit grant
  msdyn_ocauthchanneltype       = 192360000       # Live chat
  msdyn_publickeyurl            = "$portalUrl/_services/auth/publickey"
  msdyn_javascriptclientfunction = "auth.getAuthenticationToken"
} | ConvertTo-Json

$response = Invoke-WebRequest `
  -Uri "$envUrl/api/data/v9.2/msdyn_authenticationsettingses" `
  -Headers $headers -Method Post -Body $authBody
$authSettingsId = $response.Headers['OData-EntityId'] -replace '.*\((.+?)\).*', '$1'
Write-Host "Created auth settings: $authSettingsId"

# Step 2: Link to live chat widget
$patchBody = @{
  "msdyn_AuthSettingsId@odata.bind" = "/msdyn_authenticationsettingses($authSettingsId)"
} | ConvertTo-Json

Invoke-RestMethod `
  -Uri "$envUrl/api/data/v9.2/msdyn_livechatconfigs($liveChatConfigId)" `
  -Headers $headers -Method Patch -Body $patchBody
Write-Host "Linked auth settings to live chat config"
```

### Verify in Admin Center

Customer Service Admin Center → Workstreams → [chat workstream] → Behaviors →
Authentication settings should show your settings record.

### Key Fields

| Field | Value | Purpose |
|-------|-------|---------|
| `msdyn_publickeyurl` | `<portalUrl>/_services/auth/publickey` | OC validates JWT signature |
| `msdyn_javascriptclientfunction` | `auth.getAuthenticationToken` | JS function name for bootstrapper (unused by SDK but required) |
| `msdyn_authenticationtype` | `192350000` | OAuth 2.0 implicit grant |
| `msdyn_ocauthchanneltype` | `192360000` | Live chat channel |

---

## Step 8 — Deploy & Restart

After code changes:

```powershell
npm run build
pac pages upload-code-site --rootPath "." --compiledPath "./dist"
```

**Site restart is REQUIRED** after:
- Changing auth settings
- Linking auth settings to chat widget
- Any security or site-setting changes

```powershell
$token = az account get-access-token --resource "https://api.powerplatform.com" `
  --query accessToken -o tsv
$headers = @{
  "Authorization" = "Bearer $token"
  "Content-Type"  = "application/json"
}
$envId  = "<environment-guid>"   # from pac env list
$siteId = "<website-guid>"       # from Get Websites API

Invoke-RestMethod `
  -Uri "https://api.powerplatform.com/powerpages/environments/$envId/websites/$siteId/restart?api-version=2022-03-01-preview" `
  -Headers $headers -Method Post
```

After deploy + restart: **clear browser cache and hard reload** (Ctrl+Shift+R).

---

## Troubleshooting

### Agent Sees "Visitor" Instead of User Name

This is the most common issue. Follow this decision tree:

#### 1. Check: Does the SDK have auth settings?

Open browser DevTools Console and look for:
```
[ChatWidget] SDK initialized. authSettings: {...}                    ← ✅ Good
[ChatWidget] SDK initialized. authSettings: null                     ← ❌ Problem
[ChatWidget] ⚠ SDK has NO authSettings — auth will be SKIPPED       ← ❌ Problem
```

**If `authSettings` is null**: The OC backend did NOT return auth settings for this
chat widget. This means the Dataverse `msdyn_authenticationsettingses` record is
missing or not linked to the `msdyn_livechatconfigs` record. Run the diagnostic
script from Step 7 to verify.

#### 2. Check: Is `getAuthToken` being called?

Look for:
```
[Auth] Created OC auth JWT for John Doe                              ← ✅ Good
[Auth] No portal user — cannot create OC auth token                  ← ❌ User not logged in
[Auth] JWT signing failed: ...                                       ← ❌ Key problem
```

**If no `[Auth]` log lines appear at all**: The SDK never calls `getAuthToken()`.
This confirms `authSettings` is null (see #1 above).

#### 3. Check: Is the public key accessible?

Test from PowerShell:
```powershell
Invoke-WebRequest -Uri "https://<your-site>.powerappsportals.com/auth-publickey" -UseBasicParsing
```
Should return 200 with PEM content. If it returns HTML, the file isn't deployed.

#### 4. Check: Navigation property casing

The PATCH to link auth settings uses `msdyn_AuthsettingsId@odata.bind` (lowercase 's').
Using `msdyn_AuthSettingsId` (capital 'S') causes an OData undeclared-property error
that silently fails — the auth settings appear created but aren't actually linked.

#### 5. Check: Site restarted after changes?

Auth settings are server-cached. After any Dataverse changes to auth settings,
you **must** restart the site via the Admin REST API.

#### Root Cause Summary Table

| Symptom | Root Cause | Fix |
|---------|-----------|-----|
| `authSettings: null` in console | Auth settings not linked in Dataverse | Run setup-chat-auth script (Step 7) |
| No `[Auth]` logs at all | SDK skips auth entirely (authSettings null) | Fix Dataverse linking, restart site |
| `[Auth] No portal user` | User not signed in to portal | Sign in first, then open chat |
| `[Auth] JWT signing failed` | Private key missing or corrupt | Re-generate key pair (Step 4a) |
| Auth was working, then stopped | Key pair rotated without updating Dataverse | Update `msdyn_publickeyurl` or re-generate |
| `"couldn't validate your public key"` when creating auth settings | Public key file not deployed yet | Deploy site first, then create auth settings |
| OData error on PATCH to link settings | Wrong casing: `AuthSettingsId` vs `AuthsettingsId` | Use `msdyn_AuthsettingsId` (lowercase 's') |

### Console: `OmnichannelChatSDK not found in module`

The SDK export structure varies between versions. Handle both patterns:
```typescript
const OmnichannelChatSDK =
  mod.OmnichannelChatSDK ?? (mod as any).default?.OmnichannelChatSDK;
```

### SDK init fails with `global is not defined`

Missing `define: { global: 'globalThis' }` in `vite.config.ts`.

### Build error: `Cannot resolve @microsoft/botframework-webchat-adapter-azure-communication-chat`

Missing ACS adapter stub. See [Step 2](#step-2--vite-configuration-critical).

### Chat connects but messages don't appear

Check `sdk.onNewMessage` callback registration. Must be called AFTER
`sdk.startChat()`, not before. Also check if `msg.content` is empty
(system messages may have no content).

---

## What Does NOT Work

| Approach | Why it Fails |
|----------|-------------|
| `@microsoft/omnichannel-chat-widget` npm package | Webpack-only; requires postcss, sanitize-html, fs, path, source-map-js — incompatible with Vite |
| LiveChatBootstrapper script + custom UI | Loads the default Microsoft OOB widget; can't customize; conflicts with custom React component |
| `window.auth.getAuthenticationToken` on Code Sites | This global is injected by the bootstrapper script which isn't loaded when using SDK directly |
| `/_services/auth/token` on Code Sites | This endpoint does NOT exist on Code Sites v2. Returns SPA HTML shell (200 OK with HTML content, not a JWT). |
| `/_services/auth/publickey` on Code Sites | Same — returns SPA HTML. Only works on traditional portals. Must self-host the public key as a static file. |
| Traditional portal auth settings (`$portalUrl/_services/auth/publickey`) | Dataverse rejects the URL with "couldn't validate your public key" because it returns HTML, not PEM. |
| `msdyn_AuthSettingsId@odata.bind` (capital 'S') | OData error: "undeclared property". Correct casing is `msdyn_AuthsettingsId` (lowercase 's'). |
| Conditional `getAuthToken` (set only if token is non-null) | If first fetch returns null, property is never set → all chats anonymous forever |
| Caching token at init time | Token may expire; SDK calls `getAuthToken` per-session; stale tokens cause silent auth failure |

---

## Design Token Reference

```css
:root {
  --cw-gradient-start: #0077b6;
  --cw-gradient-end: #00b4d8;
  --cw-primary: #0077b6;
  --cw-user-bubble: #0077b6;
  --cw-user-text: #ffffff;
  --cw-agent-bubble: #ffffff;
  --cw-agent-text: #2d3748;
  --cw-chat-bg: #f8fafc;
  --cw-input-bg: #ffffff;
  --cw-input-border: #e2e8f0;
  --cw-send-btn: #0077b6;
  --cw-system-msg: #e2e8f0;
  --cw-system-text: #64748b;
}
```

---

## Bundle Size Notes

- SDK + dependencies adds ~845 KB to the bundle
- `jose` library adds ~8 KB gzipped
- Use code-splitting (`React.lazy()`) to keep the main bundle fast
- The SDK chunk loads only when the chat button is clicked
- PAC CLI `pac pages upload-code-site` may fail on stale bundle files locked
  by OneDrive — remove ReadOnly/ReparsePoint files manually first

---

## Custom Context Variables (Agent Toast Notifications)

To pass pre-chat form data (name, email, question) to the agent's toast
notification when a new chat arrives:

### ⚠ CRITICAL: 4-Field Limit on Toast Notifications

> **Dynamics 365 notification templates support a maximum of 4 notification fields.**
> If you need more than 4 context values, you must choose which 4 are most important
> for the toast. Additional context can still be passed via `customContext` and will
> appear in the conversation transcript / context panel — just not on the toast.
>
> Source (as of March 2026): [MS Learn — Manage notification settings and templates](https://learn.microsoft.com/en-us/dynamics365/customer-service/administer/notification-templates)
> (under "Step 2: Create the notification fields" → Note: "You can configure up to four notification fields only.")
>
> **Action**: This article may be updated or moved. Search MS Learn for the latest version next time this topic comes up.

### 1. Send Custom Context in `startChat()` — Standard Pattern

```typescript
// ── Standard context variable pattern ──
// Use simple variable names (no "Contact" prefix) matching workstream registration.
// Always null-guard with ?? ''.
const customContext: Record<string, { value: string; isDisplayable: boolean }> = {
  Name:             { value: formName ?? '',     isDisplayable: true },
  Email:            { value: formEmail ?? '',    isDisplayable: true },
  Question:         { value: formQuestion ?? '', isDisplayable: true },
  CustomerQuestion: { value: formQuestion ?? '', isDisplayable: true },  // Redundant copy — see note below
};
if (portalUser?.contactId) {
  customContext.portalcontactid = { value: portalUser.contactId, isDisplayable: false };
}

await sdk.startChat({ customContext });
```

**Why `CustomerQuestion` as a duplicate?** During bot escalation, the bot's
`ManualTransferContext` may overwrite `Question` with an empty value (see below).
Having a redundant `CustomerQuestion` ensures the notification template can
reference the original question even if `Question` gets clobbered.

### 2. Register Context Variables in Admin Center

**Customer Service Admin Center → Workstreams → [chat workstream] → Context variables:**
- Add `Name` (type: Text)
- Add `Email` (type: Text)
- Add `Question` (type: Text)
- Add `CustomerQuestion` (type: Text) — redundant backup

### 3. Configure Toast Notification Template (Max 4 Fields!)

**Admin Center → Productivity → Notification templates → [Incoming chat notification]:**
- Add notification fields with slugs: `{Name}`, `{Email}`, `{Question}` (or `{CustomerQuestion}`)
- **Remember: max 4 fields per template** — choose wisely
- These appear in the agent's toast notification when a new chat arrives

> **Note**: For authenticated chat, the agent also sees the customer name from
> the contact record. Custom context provides additional info like the question
> they typed in the pre-chat form.

### 4. Copilot Studio Bot — First Node Must Be a Question Node

**CRITICAL**: When a Copilot Studio bot is on the workstream, the bot intercepts the
chat before it reaches a human agent. To capture context variables passed via
`customContext`, the **first node in the bot's greeting/escalate topic MUST be a
Question node** that asks for the context variable.

The Question node acts as a "receiver" — when `customContext` includes a matching
variable name (e.g. `Question`), the bot auto-populates the variable from the
incoming context instead of asking the user. Without this Question node, the bot
has no mechanism to capture the `customContext` values into its variables.

### 5. Bot Escalation — ManualTransferContext Without Question

**CRITICAL**: When the bot escalates to an agent using `ManualTransferContext`,
**do NOT include `Question` in `contextVariables`** if the bot didn't successfully
capture it via a Question node. Including `Question: =Global.Question` when
`Global.Question` is empty **overwrites** the original `customContext.Question`
value with an empty string — the agent's toast shows blank.

```yaml
# ✅ CORRECT — only forward variables the bot actually captured
- kind: TransferConversationV2
  transferType:
    kind: TransferToAgent
    messageToAgent: "Check the chat transcript for customer details."
    context:
      kind: ManualTransferContext
      contextVariables:
        Name: =Global.Name
        Email: =Global.Email
        # Do NOT include Question here if the bot didn't capture it!
```

```yaml
# ❌ WRONG — overwrites Question with empty string
    context:
      kind: ManualTransferContext
      contextVariables:
        Question: =Global.Question       # ← overwrites original with ''
        Name: =Global.Name
        Email: =Global.Email
```

**Alternative**: Use `CustomerQuestion` as the notification slug instead of
`Question`, since the bot's `ManualTransferContext` doesn't list it and the
original `customContext.CustomerQuestion` value survives the escalation.

---

## End-to-End Setup Checklist

Use this checklist when setting up authenticated Omnichannel chat on a new
Power Pages Code Site:

- [ ] **Omnichannel provisioned** in Dynamics 365 environment
- [ ] **Live chat workstream** created in CS Admin Center
- [ ] **Chat widget** created within the workstream; note `orgUrl`, `orgId`, `widgetId`
- [ ] **npm packages installed**: `@microsoft/omnichannel-chat-sdk`, `jose`
- [ ] **Vite config** has ACS adapter stub (Rollup + esbuild) and `global: 'globalThis'`
- [ ] **RSA-2048 key pair** generated: `public/auth-publickey` + `keys/oc-auth-private.pem`
- [ ] **`.gitignore`** includes `keys/` and `*.pem`
- [ ] **`auth.ts`** imports `jose` + private key via `?raw`, signs JWTs with `sub: contactId`
- [ ] **`ChatWidget.tsx`** sets `getAuthToken` unconditionally on `chatSDKConfig`
- [ ] **App.tsx** wraps ChatWidget in `<ChatErrorBoundary><Suspense>...</Suspense></ChatErrorBoundary>`
- [ ] **Deploy site** first: `pac pages upload-code-site --rootPath "." --compiledPath "./dist"`
- [ ] **Verify** `/auth-publickey` returns 200 with PEM content (not HTML)
- [ ] **Create auth settings** in Dataverse via PowerShell (setup-chat-auth script)
- [ ] **Verify linking**: diagnostic script shows `_msdyn_authsettingsid_value` is set
- [ ] **Enable in Admin Center**: Workstreams → Behaviors → Authentication settings dropdown
- [ ] **Restart site** via Admin REST API
- [ ] **Clear browser cache** and hard reload (Ctrl+Shift+R)
- [ ] **Test**: Sign in → open chat → console shows `[Auth] Created OC auth JWT` → agent sees real name
- [ ] **Production TODO**: Move JWT signing to Azure Function (don't bundle private key in client code)


## Enhanced Widget Features (v2 — Standard Going Forward)

The following features are now **standard** for all new chat widget implementations.
They are implemented in the ChatWidget React component and CSS, and do NOT require
additional npm packages or external scripts.

### 1. Pre-Chat Hero Section

A branded hero area above the pre-chat form with:
- **3 overlapping avatar circles** (gradient-colored, with icons)
- **Pulsing "Online" status badge** (green dot + animation)
- **"Start a conversation"** heading + subtitle
- Uses the project's brand colours (e.g., a deep brand-colour gradient)

```tsx
<div className="cw-hero">
  <div className="cw-hero-avatars">
    <div className="cw-hero-avatar cw-hero-avatar-1"><UserIcon size={20} /></div>
    <div className="cw-hero-avatar cw-hero-avatar-2"><Bot size={20} /></div>
    <div className="cw-hero-avatar cw-hero-avatar-3"><UserIcon size={20} /></div>
  </div>
  <span className="cw-online-badge"><span className="cw-online-dot" />Online</span>
  <h3 className="cw-hero-title">Start a conversation</h3>
  <p className="cw-hero-subtitle">We're here to help!</p>
</div>
```

### 2. Sound Notifications

- **Toggle button** in header (Volume2/VolumeX icons) — persisted to `localStorage`
- Plays a **Web Audio API chime** (two-tone oscillator, 0.3s) on each incoming message
- No external audio files needed — fully synthesized in code
- Respects user's mute preference across sessions

```typescript
function playNotificationSound() {
  const ctx = new AudioContext();
  const osc = ctx.createOscillator();
  const gain = ctx.createGain();
  osc.connect(gain); gain.connect(ctx.destination);
  osc.frequency.setValueAtTime(880, ctx.currentTime);
  osc.frequency.setValueAtTime(1100, ctx.currentTime + 0.1);
  gain.gain.setValueAtTime(0.15, ctx.currentTime);
  gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.3);
  osc.start(); osc.stop(ctx.currentTime + 0.3);
}
```

### 3. Unread Message Badge

- Red badge on the FAB with count (or "9+" for >9)
- Badge appears with pop animation when new messages arrive while minimised
- Cleared when user opens the panel

### 4. Session Persistence (Reconnect on Page Navigation)

- Chat token saved to `localStorage` with 1-hour TTL
- On component mount, checks for saved session and auto-reconnects
- Restores message history via `sdk.getMessages()`
- Cleared on end-chat or TTL expiry

```typescript
// Save after startChat
const token = (sdk as any).chatToken;
if (token) saveSession(typeof token === 'string' ? token : JSON.stringify(token));

// Reconnect on mount
await sdk.startChat({ liveChatContext: JSON.parse(savedToken) });
const history = await sdk.getMessages();
```

### 5. Open/Close Animation

- Panel uses CSS `transform + opacity` transition (0.25s ease-out)
- Scale from 0.95 → 1.0 with translateY slide-up
- `isVisible` state triggers animation class after render via `requestAnimationFrame`
- Close animates out before unmounting (200ms delay)

### 6. Markdown Rendering

Agent/bot messages are parsed for basic markdown:
- `**bold**` → `<strong>`
- `*italic*` → `<em>`
- `` `code` `` → `<code>`
- `[link](url)` → `<a>` (opens in new tab)
- `- list items` → `<ul><li>`
- `\n` → `<br/>`

Uses `dangerouslySetInnerHTML` with manual HTML entity escaping (`&`, `<`, `>`).
User messages are NOT markdown-rendered — only HTML-escaped.

### 7. Agent/Bot Avatars

- Small 24px avatar circle beside each agent message
- **Bot messages**: teal gradient avatar with Bot icon
- **Human agent messages**: gold gradient avatar with User icon
- Detection via `isBot()` — checks sender name for "bot", "copilot", "virtual", "assistant", "ai", "cps"
- Sender name displayed below avatar in small muted text

### 8. Suggested Action Buttons

- Rendered as pill-shaped outline buttons below the message area
- Clicking sends the action value as a message and clears the buttons
- Picks up `msg.suggestedActions` from the SDK's `onNewMessage` callback
- Styled with brand accent border + hover fill

### 9. File Attachments

- Paperclip icon in input bar opens native file picker
- Accepts: images, PDF, Word, text, CSV, Excel
- Max size: 25 MB (validated client-side)
- Uses `sdk.uploadFileAttachment(file)`
- Shows `📎 filename` as a user message on send

### 10. Emoji Picker

- Smile icon toggles a compact emoji grid (20 common emojis)
- Clicking an emoji appends it to the input text
- Grid slides up with animation
- Closes after selection or when the smile icon is toggled off

### Lucide Icons Used

```typescript
import {
  MessageSquare, X, Send, Minimize2,
  Volume2, VolumeX, Paperclip, Smile,
  Bot, User as UserIcon
} from 'lucide-react';
```

### CSS Custom Properties Used

The widget references these CSS variables (with fallback values):

| Variable | Default | Usage |
|----------|---------|-------|
| `--chat-accent` | `#00C9A7` | Primary accent, FAB, send button, user bubbles |
| `--chat-accent-light` | `#00E6BE` | Hover states |
| `--chat-brand-primary` | `#00382F` | Header, hero gradient |
| `--chat-brand-secondary` | `#002A23` | Hero gradient end |
| `--chat-bg` | `#0A0A0A` | Messages area background |
| `--chat-panel-bg` | `#1A1A1A` | Panel background, input bar |
| `--chat-input-bg` | `#2A2A2A` | Input fields, agent bubbles |
| `--chat-border` | `#3A3A3A` | Borders |
| `--chat-agent-avatar` | `#C4A35A` | Agent avatar gradient |
| `--chat-bot-avatar` | `#00A88E` | Avatar gradient |
| `--chat-error` | `#E63946` | Error text, unread badge |
| `--font-primary` | `'Inter'` | Font family |

> **Key takeaway:** When building a new chat widget, implement ALL 10 features above
> as standard. They add ~12 KB gzipped to the lazy-loaded chunk and dramatically
> improve the UX over a bare chat panel.

---

## Knowledge-Article Citations & Copilot Studio Citation Chrome

> **Added v3.2.0 (verified Jul 2026).** When a Copilot Studio agent answers from a
> knowledge source, its **built-in citation chrome leaks into the message `content`**
> as **Private-Use-Area Unicode markers** (`U+E000`–`U+F8FF`) wrapping a citation
> title whose spaces are replaced by `~`. A custom widget that renders `content` as
> text shows those markers as **“tofu” boxes**, e.g.:
>
> ```text
> …treat it as an emergency⬛cite⬛Reporting~a~suspected~burst~water~main~or~street~leak⬛.
> ```
>
> The public URL is **not** in the inline text. Fixing this needs **both** the widget
> and the agent.

### A. Widget — safe link rendering (preferred over `dangerouslySetInnerHTML`)

Render agent/system messages through a helper that (1) strips citation chrome,
(2) rewrites internal CRM article URLs to the public portal article page, and
(3) builds **real React `<a>` elements** (no `innerHTML`, `http(s)` only — XSS-safe).
User messages stay plain text.

```tsx
import { type ReactNode } from 'react';

function renderMessageContent(raw: string): ReactNode {
    if (!raw) return raw;
    const origin = typeof window !== 'undefined' ? window.location.origin : '';
    const text = raw
        // 1) strip C0/C1 control chars (keep \t \n) + Private-Use-Area citation markers
        .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F\uE000-\uF8FF]/g, '')
        // 2) internal D365 article URL -> public portal page (HashRouter /knowledge/:id route)
        .replace(
            /https?:\/\/[^\s)]*dynamics\.com[^\s)]*[?&]articleId=([0-9a-fA-F-]{36})[^\s)]*/gi,
            (_m, id) => `${origin}/#/knowledge/${id}`,
        );
    // 3) parse Markdown links [title](url) AND bare URLs into real anchors
    const re = /\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)|(https?:\/\/[^\s)]+)/g;
    const nodes: ReactNode[] = [];
    let last = 0, key = 0, m: RegExpExecArray | null;
    while ((m = re.exec(text)) !== null) {
        if (m.index > last) nodes.push(text.slice(last, m.index));
        const url = m[2] ?? m[3]!;
        nodes.push(
            <a key={`lnk-${key++}`} href={url} target="_blank"
               rel="noopener noreferrer" className="cw-chat__link">{m[1] ?? url}</a>,
        );
        last = re.lastIndex;
    }
    if (last < text.length) nodes.push(text.slice(last));
    return nodes.length ? nodes : text;
}
```

```css
.cw-chat__link { color: var(--chat-accent, #1273d4); font-weight: 600;
    text-decoration: underline; word-break: break-word; }
.cw-chat__msg--user .cw-chat__link { color: #fff; }
```

> Feature 6 (Markdown Rendering) uses `dangerouslySetInnerHTML`. For links,
> **prefer the React-element approach above** — it avoids `innerHTML` entirely and
> is inherently XSS-safe (only `http(s)` anchors are ever emitted). The PUA/control
> strip is defensive: even if the agent still leaks citation chrome, no tofu shows.

### B. Agent — emit a real Markdown link, forbid built-in citations

In the Copilot Studio agent's GPT instructions (botcomponent `*.gpt.default` `data`
YAML), tell the model to cite as a plain Markdown link and to suppress the
auto-citation chrome. Publish with `pac copilot publish --bot <botid>`:

> At the very end of your reply, add a new line linking the source as a Markdown
> link **exactly** in this form: `[ARTICLE TITLE](ARTICLE URL)`, using the full
> `https` URL returned by the tool. Do **NOT** use automatic or inline citations,
> citation markers, footnote numbers like `[1]`, tildes, or any special characters
> — only the plain Markdown link.

Firmly forbidding the built-in citation is what stops the PUA/`~` chrome; the widget
then turns `[title](url)` into a clean, clickable, new-tab link.

### C. Inspecting raw bot output

Copilot Studio transcripts live in the Dataverse `conversationtranscript` table
(`content` = JSON; `isDesignMode` = `true` for the test pane, `false` for a live
channel). Query it to see the exact bytes the model emitted when debugging citation
formatting.

### D. Launcher clipping the site footer

On some portals the FAB sits on top of the site's dark footer bar. Raise the
container: `.cw-chat { bottom: 40px; }` (mobile `bottom: 28px;`) so the launcher
clears the footer.

> **Key takeaway:** Copilot Studio's knowledge citations are **not** plain text —
> they arrive as Private-Use-Area Unicode + `~`-encoded titles. Strip that chrome in
> the widget, rewrite internal article URLs to the public portal page, render links
> as React `<a>` elements (not `innerHTML`), and instruct the agent to emit a plain
> `[title](url)` link with no built-in citations.
