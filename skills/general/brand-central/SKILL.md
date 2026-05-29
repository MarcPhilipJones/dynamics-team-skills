---
name: brand-central
description: Source on-brand Microsoft visual assets from Brand Central (brandcentral.microsoft.com) for demos, decks, web artifacts, Power Pages, and Code Apps. Use when the user asks to "find a Microsoft logo", mentions "Brand Central", needs a "product icon", "official Microsoft asset", "Copilot icon", "M365 icon", "Dynamics icon", "Azure icon", a "branded hero image", or a "demo screenshot" with Microsoft branding. Covers navigation, search, asset selection by use-case, file-format decision logic, usage and attribution rules, and integration patterns into common deliverables.
---

# Brand Central

Brand Central (`https://brandcentral.microsoft.com`) is Microsoft's single source of truth for official imagery and branding — logos, product icons, photography, illustrations, templates, fonts, colour, video, and the brand guidelines themselves. This skill exists so demos, decks, and any other deliverable use **the right asset, in the right format, with the right usage rights** — without falling back to web-search screenshots or stale icon packs.

> Brand Central requires interactive Microsoft corp auth (Entra ID / MSAL). It is **not scriptable** — there is no public REST API and bulk-download tooling is not recommended. This skill is purely procedural / navigational.

## When to use this skill

- Building a deck and need an official Microsoft, Microsoft 365, Dynamics 365, Power Platform, Azure, or Copilot product icon
- Sourcing a hero image for a demo intro slide, customer-facing web artifact, or Power Pages site
- Picking a favicon or app icon for a Code App or SPA
- Needing a screenshot or product render that is **on-brand** rather than scraped from a marketing page
- Checking trademark / attribution rules before publishing an asset externally
- Picking between SVG / PNG / EPS for a given surface

If the user only wants generic stock imagery (people in offices, abstract concept shots), use `image-selection-guidance` instead — Brand Central is for **Microsoft-branded** assets.

## Navigation map

The site is organised by **asset type** with secondary **product / theme** facets.

| Top-level surface | Use for |
|---|---|
| **Logos** | Microsoft master brand, product wordmarks, partner logos, "Microsoft Partner" badges |
| **Product Icons** | App-tile / chiclet icons for M365 apps, Dynamics 365, Power Platform, Azure services, Copilot |
| **Photography** | Authentic Microsoft photography — people, devices, places — already cleared for use |
| **Illustrations** | Editorial illustrations, concept visuals, scenario art |
| **Templates** | PowerPoint, Word, email signatures, social cards (use these first — they save hours of restyling) |
| **Fonts** | Segoe UI family, Cascadia, brand-approved fallbacks |
| **Colour** | Brand palettes with HEX / RGB / CMYK values |
| **Video** | B-roll, product spots, intro stings |
| **Brand Guidelines** | The "why" — voice, tone, do/don't rules, accessibility guidance |

### Search and filter

- The main search box is keyword-based. Strong queries combine a **product name** with the **asset type**: `Copilot product icon`, `Dynamics 365 hero image`, `Azure service icons SVG`.
- Use the left-hand **filters** to narrow by:
  - **File type** (SVG, PNG, JPG, EPS, PPTX, MP4)
  - **Orientation** (landscape, portrait, square)
  - **Colour** (light, dark, mono)
  - **Usage rights** (internal-only, partner-shareable, public)
  - **Date added** (sort by newest when a product has been recently rebranded — Copilot icons in particular evolve)
- Bookmark the search URL once the filters are right — Brand Central preserves query state in the URL, so a saved filter set is reusable across sessions.

### Common pitfall

Search for product icons by the **current product name**, not the legacy name. Examples: `Microsoft 365 Copilot` (not `Office Copilot`), `Dynamics 365 Customer Service` (not `D365 CSI`), `Azure AI Foundry` (not `Azure AI Studio`). Brand Central retires aliases quickly; legacy terms return zero or stale results.

## Asset selection — pick the right asset for the surface

| Surface | Asset type | Preferred format | Notes |
|---|---|---|---|
| Deck title / section divider | Photography or illustration hero | PNG (full-bleed, 16:9, ≥3000px wide) | Drop into PowerPoint as background image; check Templates first for a pre-built slide |
| Deck product slide | Product icon | SVG (preferred), PNG @ 2x as fallback | Use the colour variant on light backgrounds, white-on-transparent variant on dark |
| Demo intro slide | "Cinematic" Microsoft photography | PNG / JPG, full-bleed | Pair with Segoe UI title; respect 1/3-2/3 composition rule from brand guidelines |
| Power Pages site logo / header | Wordmark logo | SVG | Upload as a web file; reference via `/logo.svg` |
| Power Pages favicon | Product icon, single-colour | PNG 32×32 + 192×192 | Convert SVG → PNG at fixed sizes; don't ship raw SVG as favicon |
| Code App / SPA logo | Product icon or wordmark | SVG (imported as React component via SVGR) | Tree-shakes to ~1–3 KB; styleable via CSS `currentColor` |
| Web artifact icon | Mono / line product icon | SVG inline | Lets the Clawpilot theme tokens drive colour via `fill: currentColor` |
| Print deliverable | Logo, photography | EPS (vector) or 300 DPI PNG / JPG | EPS preserves sharpness at any scale |
| Video thumbnail / social card | Photography crop or composite | JPG 1200×630 | Use a Brand Central template if one exists |

### Format decision logic (short version)

- **Need it crisp at any size, going on a web surface?** → SVG
- **Going into a deck, an email, or a PNG-only system?** → PNG @ 2× the rendered size
- **Going to print or a 4K video?** → EPS or a 300 DPI raster
- **It's a favicon?** → Never SVG; always pre-rendered PNG at standard sizes

## Usage and attribution rules

Brand Central tags every asset with a **usage right**. Always check the tag before publishing externally.

| Tag | Means | Where it's safe |
|---|---|---|
| **Microsoft internal only** | FTE-only, NDA-equivalent | Internal decks, internal demos, training, sandbox environments |
| **Partner-shareable** | Partners and customers under NDA | Customer demos, partner co-sell decks, scoped pre-sales |
| **Public** | No restriction | Public-facing web, public blog posts, conference materials, GitHub repos |

### Hard rules (from the brand guidelines)

- **Never recolour locked logos.** Microsoft wordmarks, product wordmarks, and Partner badges must use the colour variants Brand Central provides — do not tint, shadow, outline, or add gradients.
- **Preserve clear space.** The brand guidelines specify minimum padding around logos (typically the height of the "M"). Don't crop tight.
- **Use ™ / ® where indicated.** Product names that ship with a trademark mark on Brand Central must keep the mark on first mention in any public surface.
- **Don't strip metadata.** The downloaded asset's EXIF / file metadata records its provenance; downstream auditing depends on it.
- **Don't pair the Microsoft logo with a customer logo as if endorsing.** Co-branded materials need legal/brand review.

If a customer asks for an asset and it's tagged "Microsoft internal only", **do not share it**. Look for a "partner-shareable" or "public" equivalent, or screenshot from a published source instead.

## Alternatives when Brand Central is unavailable

If Brand Central is down, the user lacks access, or the asset isn't there:

| Source | URL | Use for |
|---|---|---|
| **Brand Tools** | `https://brandtools.microsoft.com` | Broader brand toolkit — templates, swag, campaign assets |
| **Microsoft Brand (public)** | `https://brand.microsoft.com` | Public-facing brand guidance, basic logo download |
| **Microsoft Learn graphics** | embedded in `https://learn.microsoft.com` articles | Product-specific architecture icons, conceptual diagrams |
| **Azure architecture icon set** | published as a downloadable PPTX on Microsoft Learn | Azure service icons for architecture diagrams |
| **Microsoft 365 / Power Platform icon repos** | community-curated SVG sets on GitHub | Bulk SVG access for prototypes (verify currency before shipping) |
| **Microsoft press kit / newsroom** | `https://news.microsoft.com` | Executive headshots, event photography, press-cleared assets |

Order of preference: **Brand Central → Brand Tools → Microsoft Learn / Brand public → press kit → community repos**. Always prefer the most authoritative source the surface allows.

## Integration patterns

### PowerPoint deck

1. Search Brand Central for a **Template** matching the deck type first — saves the most time.
2. Download product icons as **SVG**; PowerPoint imports SVG natively and preserves vector edit-ability.
3. For hero / divider slides, download PNG at ≥3000 px wide, place as background, send to back, add a 30–60% black overlay if text overlays it.
4. Use Segoe UI for body text (Microsoft default); Aptos for newer Microsoft 365 templates if the template uses it.

### Power Pages

1. Upload the SVG / PNG via the Power Pages maker → **Web Files**.
2. Set the MIME type explicitly (`image/svg+xml` for SVGs — some tenants default to `application/octet-stream`).
3. Always add meaningful `alt` text. For decorative-only brand imagery, use `alt=""` (empty, not omitted).
4. For above-the-fold hero images, set `loading="eager"`; everything else `loading="lazy"`.

### Code App / SPA

1. Drop SVGs into `src/assets/` and import via SVGR: `import { ReactComponent as CopilotIcon } from './assets/copilot.svg';`.
2. Use `fill="currentColor"` in the SVG source so the icon picks up the surrounding text colour.
3. For favicons, generate PNGs at 16, 32, 192, 512 px and reference them in `index.html` `<link rel="icon">` tags.
4. Never ship raw vendor SVGs without an SVGO pass — Brand Central exports often include editor metadata that bloats the bundle.

### Web artifacts (Clawpilot theme)

1. Use mono / line product icons so the Clawpilot theme tokens (`--color-accent`, `--color-text-primary`) drive the colour via `fill: currentColor`.
2. Inline SVGs are preferable to `<img>` for icons — they're themeable and accessible.
3. Always add `<title>` inside the SVG and `role="img"` for accessibility.

## Quick checklist before shipping

- [ ] Asset is from Brand Central or another authoritative source (not web-scraped)
- [ ] Usage-rights tag is compatible with the audience (internal / partner / public)
- [ ] Format matches the surface (SVG for web, PNG for decks, EPS for print)
- [ ] Product name is current (no legacy aliases)
- [ ] Logo / wordmark colour, padding, and trademark marks are preserved
- [ ] Alt text added if the asset is on a web surface
- [ ] SVG run through SVGO if shipped in a JS bundle

## Common failure modes

- **Wrong icon era** — Copilot iconography in particular has changed multiple times. Always sort by newest and verify against the public Microsoft 365 launcher.
- **Light-on-light or dark-on-dark** — Brand Central ships colour variants for a reason. Pick the variant that contrasts with the background; never recolour the logo to "fix" contrast.
- **SVG renders as a broken link in Power Pages** — almost always a MIME-type issue; set `image/svg+xml` explicitly on the web file record.
- **Icon looks pixelated in a 4K demo** — using PNG @ 1× instead of SVG. Switch to SVG, or re-export PNG at 2–3× the rendered size.
- **Pre-sales deck flagged by brand review** — usually a recoloured logo or a partner badge used outside a co-sell context. Replace with the canonical Brand Central variant.
