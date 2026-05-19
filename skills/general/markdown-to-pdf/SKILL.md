---
name: markdown-to-pdf
description: >
  Use when the user asks to "generate a PDF", "convert markdown to PDF",
  "create a branded PDF", "export to PDF", or "make a handout". Converts
  markdown files to professionally styled PDFs with custom CSS branding,
  pre-rendered Mermaid diagrams, and A4 page formatting.
version: 1.0.0
author: Grant
tags:
  - pdf
  - markdown
  - mermaid
  - branding
  - documentation
---

# Markdown to Branded PDF

> **Trigger**: "Generate a PDF from this markdown" / "Create a branded handout"

Converts a `.md` file into a professionally styled PDF with custom CSS,
pre-rendered Mermaid diagrams, headers/footers, and corporate branding.

## Prerequisites

- Node.js installed (`node --version`)
- `md-to-pdf` installed globally: `npm install -g md-to-pdf`
- `@mermaid-js/mermaid-cli` installed globally: `npm install -g @mermaid-js/mermaid-cli`

## Step-by-Step Procedure

### Phase 1: Create CSS Stylesheet

Create a `.css` file alongside the markdown with your brand colours and typography.

Key elements to include:

```css
@page {
  size: A4;
  margin: 25mm 20mm 30mm 20mm;
  @top-center { content: "CONFIDENTIAL"; font-size: 8pt; }
  @bottom-left { content: "Document Title"; font-size: 8pt; }
  @bottom-right { content: "Page " counter(page) " of " counter(pages); font-size: 8pt; }
}

body { font-family: 'Inter', sans-serif; font-size: 10.5pt; }
h1 { color: #00382F; border-bottom: 3px solid #C4A35A; }
thead th { background-color: #00382F; color: white; }

/* CRITICAL: Constrain images to prevent page overflow */
img {
  max-width: 100%;
  max-height: 200px;
  display: block;
  margin: 12px auto;
  page-break-inside: avoid;
}
```

### Phase 2: Add Frontmatter to Markdown

Add YAML frontmatter at the top of the `.md` file pointing to the CSS:

```yaml
---
stylesheet: my-style.css
pdf_options:
  format: A4
  margin: 25mm 20mm 30mm 20mm
  printBackground: true
  displayHeaderFooter: false
---
```

### Phase 3: Pre-Render Mermaid Diagrams

**CRITICAL:** `md-to-pdf` does NOT render Mermaid code blocks — it displays them as raw code. You MUST pre-render diagrams to images.

1. Create a `diagrams/` folder alongside the markdown file.
2. Save each Mermaid diagram as a `.mmd` file:

```
diagrams/
├── flow1.mmd
├── flow2.mmd
```

3. Render to PNG using `mmdc`:

```powershell
Get-ChildItem ".\diagrams\*.mmd" | ForEach-Object {
    $out = $_.FullName -replace '\.mmd$', '.png'
    mmdc -i $_.FullName -o $out -b transparent -w 900
}
```

4. Replace mermaid code blocks in the markdown with image references:

```markdown
![Flow Diagram](diagrams/flow1.png)
```

### Phase 4: Diagram Sizing Rules

| Layout | Use When | Notes |
|--------|----------|-------|
| **LR (left-right)** | 7 or fewer short-label nodes in a single chain | Fits A4 width if labels are ≤15 chars |
| **TD (top-down)** | Branching logic, decision diamonds | Can get tall — keep to ≤8 nodes vertically |
| **Pre-render width** | Always render at `-w 900` or less | Wider renders overflow A4 margins |
| **CSS max-height** | Set `max-height: 200px` on `img` | Prevents tall diagrams breaking across pages |

**If a diagram has too many nodes for one direction:**
- Split into multiple smaller diagrams
- Use very short labels (1–2 words per node)
- Remove line breaks — use single-line labels

### Phase 5: Generate PDF

```powershell
# Close any existing PDF viewer first
Stop-Process -Name "Acrobat" -ErrorAction SilentlyContinue

# Generate from the directory containing the .md and .css
Set-Location "path/to/folder"
md-to-pdf my-document.md --launch-options '{"args": ["--no-sandbox"]}'

# Open the result
Start-Process ".\my-document.pdf"
```

### Phase 6: Iterate

Common issues after first generation:

| Problem | Fix |
|---------|-----|
| Diagrams show as raw code | Mermaid not pre-rendered — go back to Phase 3 |
| Diagrams overflow page width | Switch LR diagrams to TD, or shorten labels |
| Diagrams break across pages | Add `max-height` CSS constraint on `img` |
| EBUSY error on generate | Close the PDF in Acrobat/Reader first |
| Fonts not loading | Use web-safe fonts or `@import` from Google Fonts in CSS |
| `@page` headers not showing | Set `displayHeaderFooter: true` in frontmatter |

## Common Mistakes & Warnings

- **NEVER rely on md-to-pdf to render Mermaid** — it renders them as code blocks. Always pre-render to PNG/SVG.
- **`\n` does not work in Mermaid for PDF** — use `<br/>` for line breaks in VS Code preview, but for PDF pre-renders, prefer single-line labels to avoid issues.
- **Emoji characters render inconsistently** — remove them from diagrams destined for PDF. Use text labels only.
- **`$pid` is a reserved PowerShell variable** — never use it in scripts. Use `$prodId` or `$productId` instead.
- **The CSS file path in frontmatter is relative** to the markdown file's location.
- **Close Acrobat/Reader** before regenerating — the file will be locked and `md-to-pdf` will fail with EBUSY.

## Key Takeaway

> Pre-render Mermaid to PNG with `mmdc`, constrain images with `max-height: 200px` CSS, use short labels, and always close the PDF viewer before regenerating.
