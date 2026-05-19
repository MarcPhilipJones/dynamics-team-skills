---
name: power-pages-setup-auth
description: >
  Use when the user asks to "add login", "set up authentication", "configure Entra ID",
  "add SSO", "protect pages", or "add role-based access". Configures Entra ID
  authentication for Power Pages Code Sites with login/logout flow and role-based
  route protection.
version: 1.0.0
author: Marc
applyTo: "powerpages.config.json,**/powerpages.config.json"
tags:
  - power-pages
  - authentication
  - entra-id
  - azure-ad
  - login
  - sso
---

# Set Up Authentication (Entra ID)

> **Trigger**: "Add Entra ID login to the site"

Configure Entra ID (Azure AD) authentication for a Power Pages Code Site,
including login/logout flows, role-based route protection, and local dev mocking.

## Prerequisites

- Site deployed at least once.
- Entra ID identity provider configured in Power Pages Design Studio
  (Settings > Authentication > Add provider > Azure Active Directory).
- At least one web role exists (see setup-webroles skill).

## Before You Start

1. Use the **Microsoft Learn MCP** to verify the current Power Pages
   authentication endpoint patterns.
2. Confirm the identity provider is configured in Design Studio.

## Step-by-Step Procedure

### Phase 1: Understand the Auth Flow

Power Pages handles authentication server-side. The SPA does NOT implement
OAuth directly. Instead:

1. **Login**: Navigate to `/_services/auth/login` or POST to
   `/Account/Login/ExternalLogin` with the provider name.
2. **Logout**: Navigate to `/_services/auth/logout`.
3. **Current user**: Fetch `/_api/users/me` or check the portal cookie.

### Phase 2: Create Auth Service

Create `src/services/auth.ts`:

```typescript
export interface PortalUser {
  id: string;
  displayName: string;
  email: string;
  roles: string[];
}

const isLocalDev = window.location.hostname === 'localhost';

export const authService = {
  login: () => {
    if (isLocalDev) {
      localStorage.setItem('mock-auth', 'true');
      window.location.reload();
      return;
    }
    // Power Pages Entra ID login
    const returnUrl = encodeURIComponent(window.location.pathname);
    window.location.href =
      `/Account/Login/ExternalLogin?provider=https://login.microsoftonline.com/&returnUrl=${returnUrl}`;
  },

  logout: () => {
    if (isLocalDev) {
      localStorage.removeItem('mock-auth');
      window.location.reload();
      return;
    }
    window.location.href = '/_services/auth/logout';
  },

  getCurrentUser: async (): Promise<PortalUser | null> => {
    if (isLocalDev) {
      // Return mock user for local development
      if (localStorage.getItem('mock-auth')) {
        return {
          id: 'mock-user-001',
          displayName: 'Dev User',
          email: 'dev@localhost',
          roles: ['Authenticated Users'],
        };
      }
      return null;
    }

    try {
      const res = await fetch('/_api/users/me');
      if (!res.ok) return null;
      return await res.json();
    } catch {
      return null;
    }
  },

  isAuthenticated: async (): Promise<boolean> => {
    const user = await authService.getCurrentUser();
    return user !== null;
  },
};
```

### Phase 3: Create Auth Context (React)

```typescript
// src/contexts/AuthContext.tsx
import { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import { authService, PortalUser } from '../services/auth';

interface AuthContextType {
  user: PortalUser | null;
  loading: boolean;
  login: () => void;
  logout: () => void;
}

const AuthContext = createContext<AuthContextType | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<PortalUser | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    authService.getCurrentUser().then(u => {
      setUser(u);
      setLoading(false);
    });
  }, []);

  return (
    <AuthContext.Provider value={{
      user,
      loading,
      login: authService.login,
      logout: authService.logout,
    }}>
      {children}
    </AuthContext.Provider>
  );
}

export const useAuth = () => {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be inside AuthProvider');
  return ctx;
};
```

### Phase 4: Create Protected Route Component

```typescript
// src/components/ProtectedRoute.tsx
import { Navigate } from 'react-router-dom';
import { useAuth } from '../contexts/AuthContext';

interface Props {
  children: React.ReactNode;
  requiredRoles?: string[];
}

export function ProtectedRoute({ children, requiredRoles }: Props) {
  const { user, loading } = useAuth();

  if (loading) return <div>Loading...</div>;
  if (!user) return <Navigate to="/" replace />;

  if (requiredRoles && !requiredRoles.some(r => user.roles.includes(r))) {
    return <Navigate to="/" replace />;
  }

  return <>{children}</>;
}
```

### Phase 5: Create Site Setting to Prevent Profile Redirect

After login, Power Pages may redirect to a profile page instead of the SPA.
Create this site setting to prevent it:

```powershell
New-SiteSetting -Name "Authentication/Registration/ProfileRedirectEnabled" -Value "false" -SiteId $siteId
```

### Phase 6: Wire Up Login/Logout in UI

Add login/logout buttons to the header component using the `useAuth` hook.

## Common Mistakes & Warnings

- **Profile redirect after login** -- If not disabled, Power Pages redirects to
  `/profile/` after Entra ID login. Set `ProfileRedirectEnabled = false`.
- **Anti-forgery token not available locally** -- Expected. Use mock auth for
  local development.
- **Provider name must match exactly** -- The ExternalLogin provider string
  must match what's configured in Design Studio (usually the Entra ID authority URL).
- **SPA does NOT do OAuth directly** -- Power Pages handles the OAuth flow
  server-side. The SPA just redirects to the login endpoint.
- **Cookie-based sessions** -- After login, the portal sets a session cookie.
  `/_api/users/me` returns current user data based on this cookie.
