---
name: power-pages-fix-profile-redirect
description: >
  Use when users are redirected to /profile after sign-in instead of the home page
  or intended URL. Fixes the "ProfileRedirectEnabled" setting, adds client-side
  defense JS on the server-rendered profile page, adds debug logging, and verifies
  the fix via Dataverse API. Works for Code Sites (v2) and traditional portals.
version: 1.0.0
author: Marc
applyTo: "powerpages.config.json,**/powerpages.config.json"
tags:
  - power-pages
  - authentication
  - profile-redirect
  - sign-in
  - login
  - fix
---

# Fix Profile Redirect After Sign-In

> **Trigger**: "redirected to profile after login", "profile page after sign-in",
> "fix profile redirect", "/profile/?ReturnUrl=", "landing on profile page"

Fix the common issue where Power Pages redirects to `/profile/?ReturnUrl=%2F`
after authentication instead of returning the user to the home page or the
URL they originated from.

## Problem Description

After signing in (via Entra ID, local login, or any identity provider), Power
Pages redirects the user to the server-rendered `/profile` page instead of
honoring the `returnUrl` parameter. This is especially problematic for Code Site
SPAs because:

1. The `/profile` page is server-rendered (uses `~/Pages/Profile.aspx` template)
2. The SPA has no `/profile` route — users see either a blank page or the
   legacy profile form instead of the React/Vue/Angular app
3. The `returnUrl` query parameter is ignored

## Root Cause

Power Pages has a site setting `Authentication/Registration/ProfileRedirectEnabled`
that defaults to `true`. When enabled, the server-side auth pipeline overrides the
`returnUrl` and redirects to `/profile/?ReturnUrl=<original>` after successful
sign-in.

### Why Previous Fix Attempts Often Fail

1. **API-only fix**: Changed the Dataverse record but not the YAML source file.
   On next deploy (`pac pages upload-code-site`), the YAML overwrites the
   Dataverse record back to `true`. **Always fix the YAML source file.**
2. **No site restart**: Changed the YAML but didn't restart the site. Server-side
   cache still uses the old value. Auth/security setting changes require a restart.
3. **Setting alone insufficient**: Edge cases (first-time login, profile completion
   flows) may still redirect to `/profile` even with the setting disabled.

## Prerequisites

- Site deployed at least once
- Authentication configured (any identity provider)
- Access to the `.powerpages-site/site-settings/` YAML files
- `az` CLI available for Dataverse token acquisition (for verification)

## Step-by-Step Procedure

### Phase 1: Fix the YAML Source of Truth

1. Open `.powerpages-site/site-settings/Authentication-Registration-ProfileRedirectEnabled.sitesetting.yml`
2. Change `value: true` to `value: false`
3. **Do NOT just change it in Dataverse** — the YAML is the source of truth and
   overwrites Dataverse on every deploy

```yaml
# BEFORE (broken)
description: Sets whether or not the portal can redirect the user to the profile page after successful sign-in. By default, it is set to true.
id: <existing-guid>
name: Authentication/Registration/ProfileRedirectEnabled
value: true

# AFTER (fixed)
description: Sets whether or not the portal can redirect the user to the profile page after successful sign-in. By default, it is set to true.
id: <existing-guid>
name: Authentication/Registration/ProfileRedirectEnabled
value: false
```

### Phase 2: Add Client-Side Defense on the Profile Page

Even with the setting fixed, add JavaScript to the server-rendered profile page
as a safety net. This handles edge cases where the server still redirects
(first login, profile completion flows, setting propagation delay).

Edit these two files (both are typically empty by default):

**File 1**: `.powerpages-site/web-pages/profile/Profile.webpage.custom_javascript.js`
**File 2**: `.powerpages-site/web-pages/profile/content-pages/<lang>/Profile.webpage.custom_javascript.js`

Add the same JavaScript to both:

```javascript
// [AUTH-FIX] Profile page redirect defense
// Runs on the server-rendered /profile page. If the user landed here
// after sign-in, redirect them to the intended destination (or home).
(function () {
  var params = new URLSearchParams(window.location.search);
  var returnUrl = params.get('ReturnUrl') || params.get('returnUrl') || params.get('returnurl');
  var destination = returnUrl && returnUrl !== '/profile' && returnUrl !== '/profile/' ? returnUrl : '/';

  console.warn('[AUTH-FIX] Profile page custom_javascript.js loaded', {
    url: window.location.href,
    returnUrl: returnUrl,
    destination: destination,
    timestamp: new Date().toISOString()
  });

  // Redirect away from the profile page to the SPA home (or returnUrl)
  console.warn('[AUTH-FIX] Redirecting from profile page to: ' + destination);
  window.location.replace(destination);
})();
```

**Why both files?** Power Pages may invoke either the root page or the
language-specific content page depending on language resolution. Adding the
script to both ensures coverage.

**Why `window.location.replace()`?** It replaces the current history entry so
the user can't press Back and land on `/profile` again.

### Phase 3: Add Debug Logging (Optional but Recommended)

Add an inline script to `index.html` (before the framework bundle) for
persistent auth debugging:

```html
<script>
  // [AUTH-DEBUG] Early auth debug logging — runs before SPA framework
  (function () {
    var loc = window.location;
    var params = new URLSearchParams(loc.search);
    var returnUrl = params.get('ReturnUrl') || params.get('returnUrl') || params.get('returnurl');
    var isProfilePage = /^\/profile/i.test(loc.pathname);
    var cookies = document.cookie;
    var hasAuthCookie = /\.AspNet\.Cookies|ARRAffinity|__RequestVerificationToken/.test(cookies);
    console.debug('[AUTH-DEBUG] Page load', {
      url: loc.href,
      path: loc.pathname,
      returnUrl: returnUrl,
      isProfilePage: isProfilePage,
      hasAuthCookie: hasAuthCookie,
      timestamp: new Date().toISOString()
    });
    if (isProfilePage && returnUrl) {
      console.warn('[AUTH-DEBUG] Detected profile redirect after sign-in! ReturnUrl=' + returnUrl);
    }
    // Check portal user object after a delay (loads async via Power Pages runtime)
    setTimeout(function () {
      var ms = window['Microsoft'];
      var user = ms && ms.Dynamic365 && ms.Dynamic365.Portal && ms.Dynamic365.Portal.User;
      console.debug('[AUTH-DEBUG] Portal user check (delayed)', {
        hasUser: !!(user && user.userName),
        userName: user ? user.userName : '(not loaded)'
      });
    }, 1500);
  })();
</script>
```

Also add `console.debug` to your auth button/service component to log user
detection state on render.

### Phase 4: Deploy + Restart + Verify

1. **Build and deploy**:
   ```powershell
   npm run build
   pac auth select --index <your-auth-index>
   pac pages upload-code-site --rootPath "." --compiledPath "./dist"
   ```

2. **Restart the site** (required — auth settings are cached server-side):
   ```powershell
   $token = az account get-access-token --resource "https://api.powerplatform.com" --query accessToken -o tsv
   $headers = @{ "Authorization" = "Bearer $token"; "Content-Type" = "application/json" }
   $envId = "<environment-guid>"
   $siteId = "<website-id-from-admin-api>"
   Invoke-RestMethod -Uri "https://api.powerplatform.com/powerpages/environments/$envId/websites/$siteId/restart?api-version=2022-03-01-preview" -Headers $headers -Method Post
   ```

3. **Verify via Dataverse API** (confirms YAML deployed correctly):
   ```powershell
   $envUrl = "<org-url>"  # e.g. https://orgXXX.crm4.dynamics.com
   $siteId = "<powerpagesiteid>"  # from powerpages.config.json or Dataverse
   $token = az account get-access-token --resource $envUrl --query accessToken -o tsv
   $headers = @{ "Authorization" = "Bearer $token"; "Accept" = "application/json" }
   $filter = "name eq 'Authentication/Registration/ProfileRedirectEnabled' and _powerpagesiteid_value eq '$siteId' and powerpagecomponenttype eq 9"
   $uri = "$envUrl/api/data/v9.2/powerpagecomponents?`$filter=$filter&`$select=name,content"
   $result = Invoke-RestMethod -Uri $uri -Headers $headers
   $content = $result.value[0].content | ConvertFrom-Json
   Write-Host "ProfileRedirectEnabled = $($content.value)"
   # Should output: ProfileRedirectEnabled = false
   ```

4. **Browser verification**:
   - Clear cache (Ctrl+Shift+R)
   - Sign in
   - Should land on `/` (home), NOT `/profile/?ReturnUrl=%2F`
   - Open DevTools Console → check for `[AUTH-DEBUG]` or `[AUTH-FIX]` messages
   - If you see `[AUTH-FIX] Profile page custom_javascript.js loaded`, the
     server-side setting didn't fully prevent the redirect, but the JS defense
     caught it and redirected home

## Related Site Settings

| Setting | Recommended Value | Purpose |
|---|---|---|
| `Authentication/Registration/ProfileRedirectEnabled` | `false` | **Primary fix** — disables server-side redirect to profile |
| `Profile/ForceSignUp` | `False` | Prevents forcing profile completion on first visit |
| `Profile/Enabled` | `true` | Keep enabled — disabling may break portal internals |
| `Header/ShowAllProfileNavigationLinks` | `false` | Hides profile nav links from header |

## Common Mistakes & Warnings

- **YAML is the source of truth** — fixing only Dataverse is futile because the
  next `pac pages upload-code-site` overwrites it. Always fix the `.sitesetting.yml` file.
- **Restart is required** — auth/security setting changes are cached server-side.
  Without a restart, the old value persists for up to 15 minutes.
- **Auth setting propagation delay** — even after restart, MS Learn docs note
  changes "can take a few minutes" to propagate. Wait 3–5 minutes if the fix
  doesn't appear immediately.
- **Don't delete the profile page** — `/profile` is a Power Pages system page
  (`~/Pages/Profile.aspx`). Deleting it can break other portal functionality.
  Use the JS defense to redirect away from it instead.
- **Both custom_javascript.js files** — add redirect JS to both the root and
  language-specific content page versions. Power Pages may invoke either one.
- **`window.location.replace()` not `href`** — using `replace()` prevents the
  user from pressing Back and landing on `/profile` again.
- **Debug logging uses `console.debug`** — not visible unless DevTools console
  filter is set to "Verbose". Low impact, high value for future debugging.

## Verification Checklist

- [ ] YAML file has `value: false`
- [ ] Dataverse API query confirms `"value":"false"` after deploy
- [ ] Site restarted after deploy
- [ ] Sign in → lands on `/` (home), not `/profile/`
- [ ] DevTools Console shows `[AUTH-DEBUG] Page load` with `isProfilePage: false`
- [ ] Direct navigation to `/profile/` → JS redirects to `/` (console shows `[AUTH-FIX]`)

## Related Skills

| Skill | When to Use |
|---|---|
| [setup-auth](../setup-auth/SKILL.md) | Initial Entra ID authentication setup |
| [restart-site](../restart-site/SKILL.md) | Restart site after auth setting changes |
| [code-sites-v2-reference](../code-sites-v2-reference/SKILL.md) | YAML overwrite behaviour, component types |
| [deploy](../deploy/SKILL.md) | First deployment |
| [upload](../upload/SKILL.md) | Incremental redeployment |
