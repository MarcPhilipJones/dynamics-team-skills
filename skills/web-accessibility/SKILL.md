---
name: web-accessibility
description: >
  Use when asked to "check accessibility", "fix contrast", "add ARIA",
  "keyboard navigation", "WCAG audit", "screen reader support", "make accessible",
  or when building new UI components, forms, modals, or dropdowns. Implements
  WCAG 2.1 AA standards for semantic HTML, keyboard navigation, ARIA attributes,
  color contrast, and testing.
version: 1.1.0
author: supercent-io (adapted for shared use)
applyTo: "**/*.tsx,**/*.css"
tags:
  - accessibility
  - a11y
  - WCAG
  - ARIA
  - keyboard-navigation
  - frontend
---

# Web Accessibility (A11y)

> **Trigger**: "Check accessibility", "Fix contrast", "WCAG audit", "Make accessible"
>
> **Source**: https://skills.sh/supercent-io/skills-template/web-accessibility

Implement WCAG 2.1 AA accessibility standards across any React + TypeScript codebase.

## When to Use This Skill

- New UI component development — designing accessible components
- Accessibility audit — identifying and fixing issues in existing sites
- Form implementation — screen reader-friendly forms
- Modals/dropdowns — focus management and keyboard trap prevention
- WCAG compliance — meeting AA standards (our default level)

## Input

- **Framework**: React + TypeScript (our stack)
- **WCAG Level**: AA (default)
- **Testing**: Chrome DevTools, axe-core, Lighthouse

---

## Step 1: Use Semantic HTML

Use meaningful HTML elements — avoid div/span soup.

- Use `<button>`, `<nav>`, `<main>`, `<header>`, `<footer>`, `<section>`
- Heading hierarchy: `<h1>` → `<h2>` → `<h3>` (never skip levels)
- Connect `<label>` with `<input>` via `htmlFor`/`id`
- Use `<ul>`/`<ol>` for lists, not styled divs

```tsx
// ❌ Bad
<div className="nav">
  <div onClick={navigate}>Home</div>
</div>

// ✅ Good
<nav aria-label="Main navigation">
  <ul>
    <li><a href="/">Home</a></li>
  </ul>
</nav>
```

```tsx
// ❌ Bad — no label
<input type="text" placeholder="Enter your name" />

// ✅ Good — label connected
<label htmlFor="name">Name:</label>
<input type="text" id="name" name="name" required />
```

---

## Step 2: Keyboard Navigation

All features must be usable without a mouse.

- **Tab / Shift+Tab** — move focus between interactive elements
- **Enter / Space** — activate buttons
- **Arrow keys** — navigate lists, menus, tabs
- **Escape** — close modals, dropdowns, popups
- **`tabindex="0"`** — make custom elements focusable
- **`tabindex="-1"`** — programmatic focus only (e.g. modal container)
- **Never use `tabindex > 0`** — it breaks natural DOM order

### React Dropdown Example

```tsx
const handleKeyDown = (e: React.KeyboardEvent) => {
  switch (e.key) {
    case 'ArrowDown':
      e.preventDefault();
      setSelectedIndex((prev) => (prev + 1) % options.length);
      break;
    case 'ArrowUp':
      e.preventDefault();
      setSelectedIndex((prev) => (prev - 1 + options.length) % options.length);
      break;
    case 'Enter':
    case ' ':
      e.preventDefault();
      if (isOpen) { onChange(options[selectedIndex].value); setIsOpen(false); }
      else { setIsOpen(true); }
      break;
    case 'Escape':
      setIsOpen(false);
      buttonRef.current?.focus();
      break;
  }
};
```

---

## Step 3: ARIA Attributes

Provide additional context for screen readers.

| Attribute | Purpose |
|---|---|
| `aria-label` | Name the element directly |
| `aria-labelledby` | Reference another element as label |
| `aria-describedby` | Additional description |
| `aria-live="polite"` | Announce changes when idle |
| `aria-live="assertive"` | Announce immediately (errors) |
| `aria-hidden="true"` | Hide decorative elements from screen readers |
| `aria-expanded` | Indicate open/closed state |
| `aria-modal="true"` | Declare a modal dialog |
| `role="dialog"` | Identify modal containers |
| `role="alert"` | Mark error/success messages |

### Accessible Modal Pattern

```tsx
function AccessibleModal({ isOpen, onClose, title, children }: Props) {
  const modalRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (isOpen) modalRef.current?.focus();
  }, [isOpen]);

  if (!isOpen) return null;

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="modal-title"
      ref={modalRef}
      tabIndex={-1}
      onKeyDown={(e) => { if (e.key === 'Escape') onClose(); }}
    >
      <div className="modal-overlay" onClick={onClose} aria-hidden="true" />
      <div className="modal-content">
        <h2 id="modal-title">{title}</h2>
        {children}
        <button onClick={onClose} aria-label="Close modal">×</button>
      </div>
    </div>
  );
}
```

### Dynamic Notifications

```tsx
<div role="alert" aria-live="assertive" aria-atomic="true">
  ⚠️ An error occurred. Please try again.
</div>
```

---

## Step 4: Color Contrast & Visual Accessibility

| Standard | Normal Text | Large Text (18px+ bold or 24px+) |
|---|---|---|
| WCAG AA | 4.5:1 | 3:1 |
| WCAG AAA | 7:1 | 4.5:1 |

Rules:
- Never convey information by colour alone — use icons/text alongside
- Always provide visible focus indicators
- **NEVER use `outline: none`** — provide a custom focus style instead

```css
/* ✅ Focus indicator */
button:focus-visible,
a:focus-visible {
  outline: 2px solid #0066cc;
  outline-offset: 2px;
}

/* ❌ NEVER do this */
button:focus { outline: none; }
```

---

## Step 5: Testing

1. **Automated**: Run axe DevTools or Lighthouse Accessibility audit
2. **Keyboard**: Tab through the entire page — can you reach and activate everything?
3. **Screen reader**: Test with NVDA (Windows) or VoiceOver (Mac)
4. **Contrast**: Use Chrome DevTools colour contrast checker

### Jest + axe-core

```tsx
import { axe, toHaveNoViolations } from 'jest-axe';
expect.extend(toHaveNoViolations);

it('should have no accessibility violations', async () => {
  const { container } = render(<MyComponent />);
  const results = await axe(container);
  expect(results).toHaveNoViolations();
});
```

---

## Checklist

### Semantic HTML
- [ ] Semantic tags used (`<button>`, `<nav>`, `<main>`, etc.)
- [ ] Heading hierarchy correct (h1 → h2 → h3)
- [ ] All form labels connected

### Keyboard
- [ ] All interactive elements reachable via Tab
- [ ] Buttons activated with Enter/Space
- [ ] Modals/dropdowns close with Escape
- [ ] Focus indicator visible

### ARIA
- [ ] `role` used appropriately
- [ ] `aria-label` or `aria-labelledby` on interactive elements
- [ ] `aria-live` for dynamic content
- [ ] Decorative elements use `aria-hidden="true"`

### Visual
- [ ] Colour contrast meets WCAG AA (4.5:1)
- [ ] Information not conveyed by colour alone
- [ ] Text resizable without breaking layout

### Testing
- [ ] 0 axe DevTools violations
- [ ] Lighthouse Accessibility score 90+
- [ ] Keyboard-only test passed

---

## Constraints

### Mandatory (MUST)
1. All features usable without a mouse (Tab, Enter, Space, arrows, Escape)
2. Focus trap in modals — focus stays inside until closed
3. All images have `alt` attributes (descriptive or empty for decorative)
4. All form inputs have associated labels

### Prohibited (MUST NOT)
1. Never remove outline (`outline: none`) without providing an alternative
2. Never use `tabindex > 0` — breaks focus order
3. Never convey information by colour alone

---

## Best Practices

1. **Semantic HTML first** — ARIA is a last resort. `<button>` beats `<div role="button">`
2. **Focus management in SPAs** — move focus to main content on route change
3. **Skip links** — provide "Skip to main content" for keyboard users
4. **Error messages** — be specific: "Email must be in format: name@example.com" not "Invalid input"

## References

- [WCAG 2.1 Quick Reference](https://www.w3.org/WAI/WCAG21/quickref/)
- [MDN ARIA](https://developer.mozilla.org/en-US/docs/Web/Accessibility/ARIA)
- [WebAIM](https://webaim.org/)
- [axe DevTools](https://www.deque.com/axe/devtools/)
- [A11y Project](https://www.a11yproject.com/)
