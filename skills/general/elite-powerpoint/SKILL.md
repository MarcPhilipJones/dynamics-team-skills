---
name: elite-powerpoint
description: >
  Use whenever a .pptx is involved — creating, editing, reading, restyling, or
  branding a slide deck. Triggers on "build a PowerPoint", "create a deck",
  "presentation", "slides", "pitch deck", "restyle the pptx", "Fluent 2 deck",
  "D365 template", or any reference to a .pptx filename. Produces editable,
  professional, on-brand decks via python-pptx + the official Microsoft D365
  template + Microsoft Fluent 2 design tokens, with a mandatory visual self-check
  loop using PowerPoint COM (Windows) or LibreOffice (cross-platform).
version: 1.0.0
author: Marc
tags:
  - powerpoint
  - pptx
  - fluent2
  - d365-template
  - python-pptx
  - design-system
  - presentation
---

# Elite PowerPoint Skill

> **Trigger**: any task touching a `.pptx` — input, output, or both.

This skill produces **editable, professional, presenter-grade decks**. Every
graphic is a native PowerPoint shape (never a raster image), every colour
follows Microsoft **Fluent 2** design tokens, and every deck is verified slide
by slide before being declared complete. The default look-and-feel uses the
official **Microsoft Dynamics 365 PowerPoint template** for hero, divider,
quote, and closing slides, with custom Fluent 2 content slides built on Blank
layouts.

> **Golden rule**: assume your first render is wrong. Render every slide,
> review each one, fix problems, render again. Do not declare success until a
> full review pass turns up zero issues.

---

## 1. When to Use This Skill

Mention any of these and this skill applies:

- "Build a PowerPoint / deck / pitch / slide deck / presentation"
- "Convert this markdown to slides"
- "Restyle / brand-align / polish this `.pptx`"
- "Read / extract / summarise the content of `*.pptx`"
- "Use the D365 template" or "use Fluent 2"
- Any path ending in `.pptx`

### Out of scope (use a different tool)

- **PowerPoint Copilot inside M365** — accept the friction list (no `.md`
  source, no local images, no scripting, no version control). Use this skill
  instead when reproducibility matters.
- **HTML / web slide decks** — use Marp, Reveal.js, or a static site.

---

## 2. Mandatory Standards (NON-NEGOTIABLE)

These rules apply to **every** deck produced by this skill.

### 2.1 Tooling

| Concern | Tool | Why |
|---|---|---|
| Generation | **Python + `python-pptx`** | Repeatable, scriptable, version-controllable |
| Template | `C:\Users\marcjones\Downloads\D365Template.pptx` | Official Microsoft D365 template |
| Visual QA | **PowerPoint COM** on Windows; LibreOffice `soffice` cross-platform | Authoritative rendering |
| Image sourcing | **NO IMAGES BY DEFAULT** | Use shapes; raster images are not editable |
| Diagrams | Native PowerPoint shapes (rectangles, ovals, arrows) | Editable in Studio |

If raster images are explicitly requested, **only use Unsplash** per workspace
policy (`copilot-instructions.md` §12). Never use AI-generated stock images.

### 2.2 Design system — Microsoft Fluent 2

Apply these tokens via constants in your generator:

```python
# Neutrals (Fluent 2)
F_WHITE     = RGBColor(0xFF, 0xFF, 0xFF)
F_BG_2      = RGBColor(0xFA, 0xFA, 0xFA)   # canvas
F_BG_3      = RGBColor(0xF5, 0xF5, 0xF5)
F_STROKE_1  = RGBColor(0xE0, 0xE0, 0xE0)   # card outline
F_STROKE_2  = RGBColor(0xD1, 0xD1, 0xD1)
F_FG_1      = RGBColor(0x24, 0x24, 0x24)   # primary text
F_FG_2      = RGBColor(0x42, 0x42, 0x42)   # secondary text
F_FG_3      = RGBColor(0x60, 0x5E, 0x5C)   # muted text

# Brand ramp (Microsoft brand)
F_BRAND_60   = RGBColor(0x11, 0x5E, 0xA3)
F_BRAND_80   = RGBColor(0x0F, 0x6C, 0xBD)  # primary
F_BRAND_100  = RGBColor(0x71, 0xAF, 0xE2)
F_BRAND_TINT = RGBColor(0xE8, 0xF1, 0xFA)
F_BRAND_TINT2= RGBColor(0xCF, 0xE4, 0xF6)

# Status
F_SUCCESS = RGBColor(0x10, 0x7C, 0x10)
F_WARNING = RGBColor(0xBC, 0x4B, 0x09)
F_DANGER  = RGBColor(0xD1, 0x34, 0x38)
```

**Per-deck accent**: pick ONE topical accent (e.g. a deep brand colour like
`#00674A`) and use it as a tertiary alongside the brand ramp. Never replace the
brand ramp wholesale.

### 2.3 Typography

| Use | Font | Size |
|---|---|---|
| Slide title | `Segoe UI Variable Display` bold | 24–28 pt |
| Section / card heading | `Segoe UI Variable Display` bold | 14–18 pt |
| Body text | `Segoe UI Variable Text` | 11 pt |
| Eyebrow / labels | `Segoe UI Variable Display` bold ALL-CAPS | 9–10 pt |
| Captions / footers | `Segoe UI Variable Text` | 9 pt |

**Forbidden**: Arial, Calibri default, mixed font families, generic bullets.

### 2.4 Colour and layout rules

- Dark backgrounds for title + closing only ("sandwich" structure). Light
  canvas (`F_BG_2`) for content.
- One colour dominates (60–70% visual weight); 1–2 supporting tones; one
  accent.
- 0.5" minimum margins.
- 0.20–0.30" gaps between cards/blocks.
- 8 px corner radius on all rounded rectangles (`adjustments[0]`).
- 4 px coloured top stripe on category cards.
- All cards have `F_STROKE_1` outline at 0.75 pt.

### 2.5 Anti-patterns (NEVER do these — hallmarks of AI-generated slides)

- **Never use a thin accent line directly under the title** — use whitespace
  or a small chip instead.
  *(Anthropic PPTX skill explicitly calls this out.)*
- Never centre body text — left-align paragraphs and lists.
- Never repeat the same layout across all content slides — vary cards, steps,
  grids, and quotes.
- Never create text-only slides — every slide needs at least one visual block.
- Never default to plain blue — use the full Fluent ramp + topical accent.
- Never style one slide and leave the rest plain — commit fully or keep simple
  throughout.
- Never use low-contrast text (light grey on cream, dark on dark).
- Never let title text wrap into a decorative element.
- Never hardcode template paths inside the deck — keep them as constants.
- Never embed credentials, tokens, or API keys in any slide note.

---

## 3. Standard Generator Skeleton

Use this scaffold for every new deck. Save as
`presentations/<deck-name>/generate.py`.

```python
"""
<Deck Title> — D365 Template + Fluent 2
"""
from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.enum.shapes import MSO_SHAPE
import os

TEMPLATE = r"C:\Users\marcjones\Downloads\D365Template.pptx"
OUTPUT   = os.path.join(os.path.dirname(__file__), "<deck-name>.pptx")

# ── Fluent 2 tokens (paste full set from §2.2) ────────────────────────
# ...

FONT_DISPLAY = "Segoe UI Variable Display"
FONT_TEXT    = "Segoe UI Variable Text"

SLIDE_W = Inches(13.333)
SLIDE_H = Inches(7.5)
MARGIN  = Inches(0.5)


def load_template():
    prs = Presentation(TEMPLATE)
    sldIdLst = prs.slides._sldIdLst
    while len(sldIdLst) > 0:
        sldId = sldIdLst[0]
        rId = sldId.get('{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id')
        if rId:
            prs.part.drop_rel(rId)
        sldIdLst.remove(sldId)
    return prs


def blank_slide(prs, bg=F_BG_2):
    slide = prs.slides.add_slide(prs.slide_layouts[66])  # Blank
    fill = slide.background.fill
    fill.solid(); fill.fore_color.rgb = bg
    return slide
```

### Reusable Fluent helpers

Always include:

- `f_textbox(...)` — zero-margin textbox with font/size/colour
- `f_card(...)` — rounded rectangle with stroke and 8 px radius
- `f_accent_card(...)` — card with 4 px coloured top stripe + heading + body
- `f_step(...)` — circular numbered token + bold title + body description
- `f_chip(...)` — pill badge with tint fill and brand label
- `f_header(slide, eyebrow, title)` — eyebrow ALL-CAPS + display title
  *(no decorative rule — see §2.5)*
- `f_footer(slide, text)` — small muted footer

A reference implementation lives in
[`presentations/generate-d365-journey.py`](../../../presentations/generate-d365-journey.py).
Copy and adapt rather than rewriting.

---

## 4. The D365 Template — Layout Cheat-Sheet

Slide size 13.333" × 7.5" (16:9).

| Index | Layout | Use for |
|---|---|---|
| 0 | Title | Light hero |
| 4 | Dark Title 1 | **Default cover** |
| 12 | Title and Content | Light bullet body |
| 13 | Title & Non-bulleted text | Profile / single-paragraph body |
| 16 | Two Column Bullet with Subheads | Two-up comparisons |
| 18 | Three Column Bullet with Subtitles | Platform breakdown grids |
| 19 | Four Column Bullet with Subtitles | Phase / step grids |
| 42 | Title and text side by side | Chat / conversation |
| 50 | Quote blue | Narrative quote |
| 53 | Alternate quote | Closing quote |
| 57–59 | Section Title gradient 1/2/3 | **Stage dividers** |
| 66 | Blank | **All custom Fluent 2 content slides** |
| 68 | Thank you 1 | Final slide |
| 70 | Closing logo slide | Sponsor / partner credits |

Rule: keep template layouts for cover/divider/quote/closing. Build all content
on **Blank (index 66)** so you have full control of Fluent 2 styling. The
template's bullet placeholders fight with custom typography — avoid them for
content.

---

## 5. Standard Slide Patterns

Pick patterns from this list. **Vary** them — never use the same pattern
twice in a row.

### 5.1 Hero (cover)

Use Dark Title 1 (layout 4). Title 36 pt bold white; subtitle 16 pt
off-white. No decorative rule.

### 5.2 Narrative quote

Use Quote layouts (50/53). 18–22 pt body, 14 pt attribution.

### 5.3 Card grid (3 or 4 categories)

`f_accent_card` × N across the canvas. Each card: 4 px stripe + 14 pt
heading + 11 pt body lines. Use this for *Touchpoints / Data / Flow* triplets
and platform overviews.

### 5.4 Numbered step grid (4 or 8 steps)

`f_step` rows in a 2-column layout. Each step: 0.46" circular brand-filled
number, 13 pt bold title, 11 pt body. Use for procedural narratives.

### 5.5 Profile card with KPI chips

Avatar circle (initials) + name (20 pt) + role + chips. Chips: tint fill,
brand text, 9.5 pt. Use for personas and customer 360 views.

### 5.6 Vehicle / object detail row of cards

3–4 cards, each with stripe + 18 pt name + secondary text + key/value rows.

### 5.7 Chat / conversation

Left context card + right column of chat bubbles. User bubbles right-aligned
in brand or topical accent; bot bubbles left-aligned in `F_BRAND_TINT`. Bubble
corner radius 14 px, no left-side stroke for filled bubbles.

### 5.8 Process loop (Trigger → Engage → Measure → Convert)

4 cards with big numerals (32 pt), 18 pt heading, bullet items, **right-arrow
shape** (`MSO_SHAPE.RIGHT_ARROW`) in `F_STROKE_2` between each pair.

### 5.9 Section divider

Use template layouts 57–59 for gradient dividers. Keep the title on these
to a single line.

### 5.10 Architecture overview (8-card grid)

4 × 2 grid of mini-cards: 9 pt eyebrow, 14 pt tech name, 10.5 pt description,
4 px stripe.

---

## 6. Visual Self-Check Loop (MANDATORY)

> Anthropic's PPTX skill is unambiguous: *"Your first render is almost never
> correct. If you found zero issues on first inspection, you weren't looking
> hard enough."*

### 6.1 Render slides to PNG (Windows — preferred)

```powershell
$out = Join-Path $PWD "review"
if (-not (Test-Path $out)) { New-Item -ItemType Directory -Path $out | Out-Null }
$pp = New-Object -ComObject PowerPoint.Application
$deck = $pp.Presentations.Open((Join-Path $PWD "<deck>.pptx"), $true, $false, $false)
foreach ($i in 1..$deck.Slides.Count) {
    $deck.Slides.Item($i).Export((Join-Path $out "slide-$i.png"), "PNG", 1920, 1080)
}
$deck.Close(); $pp.Quit()
```

### 6.2 Render slides to JPG (cross-platform fallback)

```bash
soffice --headless --convert-to pdf <deck>.pptx
pdftoppm -jpeg -r 150 <deck>.pdf slide
```

### 6.3 Inspection checklist

For **every** slide, look for:

- [ ] Overlapping elements (text through shapes, lines through words)
- [ ] Text overflow at edges or off the bottom of the slide
- [ ] Decorative elements positioned for one-line text but the title wrapped
- [ ] Source citations or footers colliding with content above
- [ ] Elements too close (< 0.3" gaps) or cards nearly touching
- [ ] Uneven gaps (cramped on one side, empty on the other)
- [ ] Insufficient margin from slide edges (< 0.5")
- [ ] Columns or grid items not aligned consistently
- [ ] Low-contrast text (light grey on cream, dark on dark)
- [ ] Low-contrast icons (dark on dark without a tinted circle)
- [ ] Text boxes too narrow causing excessive wrapping
- [ ] Leftover placeholder content (`Lorem`, `xxxx`, `[insert]`)
- [ ] Decorative accent rule under the title (forbidden — §2.5)
- [ ] Mixed font families across slides
- [ ] Bullet lists where a card grid would be clearer

### 6.4 Verification loop

1. Generate slides → render → inspect.
2. List issues found. **If you found none, look again more critically.**
3. Fix issues in the generator.
4. Re-render only affected slides.
5. Re-inspect — one fix often introduces another problem.
6. Repeat until a full pass produces zero new issues.

**Do not declare success until at least one fix-and-verify cycle has run.**

### 6.5 Content QA (required before declaring done)

```powershell
python -m markitdown <deck>.pptx | Select-String -Pattern "xxxx|lorem|ipsum|insert|TODO" -CaseSensitive:$false
```

If the search returns matches, fix them.

---

## 7. Reading & Editing Existing Decks

### 7.1 Extract text content

```powershell
pip install "markitdown[pptx]"
python -m markitdown existing.pptx > content.md
```

### 7.2 Inspect layouts in a template

```python
from pptx import Presentation
p = Presentation(r"path\to\template.pptx")
print("SIZE:", p.slide_width, "x", p.slide_height)
for i, lay in enumerate(p.slide_layouts):
    print(i, lay.name)
```

### 7.3 Edit specific slides safely

- Open with `python-pptx`, mutate only the targeted shapes, save.
- Never iterate `slide.shapes` and mutate during iteration — collect refs
  first.
- Preserve speaker notes by leaving the notes slide untouched.

---

## 8. Common Failure Modes (and the fix)

| Symptom | Cause | Fix |
|---|---|---|
| Chat bubbles overflow off the bottom | Bubble heights estimated too tall | Reduce per-line height factor (0.24 in) and trim padding |
| `'int' object has no attribute 'inches'` | Subtracting two `Length` values returns `int` (EMU) | Convert with `value / 914400.0` to get inches as float |
| Card stroke shows through accent stripe | Stripe drawn before card | Always draw card first, stripe second |
| Number-circle shows wrong digits | Default placeholder text inherited | Always `tf.clear()` then add a fresh run |
| Title font reverts to Calibri | Forgot to set `run.font.name` | Set `font.name = FONT_DISPLAY` on every run |
| Text invisible on dark hero | Inherited from body theme | Explicitly set `font.color.rgb = F_WHITE` |
| Shapes not editable in Studio after open | Used `add_picture` for what should be a shape | Use `add_shape(MSO_SHAPE.*)` instead |
| Corner radius is rectangular | `adjustments[0]` not set on rounded rect | Set `adj = (target_inches) / (min_dim_inches/2)` clamped 0–0.5 |
| Bullet placeholder shows phantom text | Template bullet placeholder kept | Use Blank layout (66) for content slides |
| Copy-pasted formula breaks rendering | Invisible Unicode from a browser | Type or programmatically generate text — never paste from a browser |

---

## 9. File and Folder Conventions

```
presentations/
└── <deck-name>/
    ├── generate.py        # The generator (this skill produces this)
    ├── source.md          # Optional markdown source
    ├── <deck-name>.pptx   # The generated output
    └── review/            # PNG renders for visual QA
        └── slide-N.png
```

Commit `generate.py` and `source.md` to git. The `.pptx` and `review/` folders
may be gitignored if rebuilds are deterministic.

---

## 10. End-to-End Workflow (the canonical flow)

1. **Read the source** (`source.md` or chat brief). Identify the narrative
   arc, personas, stages, and required artefacts.
2. **Plan the deck** — list every slide with its pattern (§5). Vary patterns.
3. **Confirm the plan** with the user before writing code.
4. **Scaffold** `generate.py` from §3.
5. **Build slides one at a time**, in narrative order. Mark progress with the
   workspace todo system if more than 3 slides.
6. **Run the generator** (`python generate.py`).
7. **Render every slide** to PNG (§6.1).
8. **Inspect** every render against §6.3.
9. **Fix → regenerate → re-inspect** until §6.4 produces zero issues.
10. **Run content QA** (§6.5).
11. **Report** the slide count, the file path (as a markdown link), and a
    one-line summary per design decision (palette, accent, fonts).

---

## 11. Skill References

- Anthropic PPTX skill — [github.com/anthropics/skills/tree/main/skills/pptx](https://github.com/anthropics/skills/tree/main/skills/pptx)
- python-pptx docs — [python-pptx.readthedocs.io](https://python-pptx.readthedocs.io)
- Microsoft Fluent 2 design tokens — [fluent2.microsoft.design](https://fluent2.microsoft.design)
- Workspace policy on imagery — your own `.github/copilot-instructions.md` (if any)
- Reference deck generator — keep your project's `presentations/generate-*.py` close by
- Reference output — your own validated `.pptx` outputs from previous runs

---

## 12. Quick Reference Card

| Need | Action |
|---|---|
| New deck | Copy `presentations/generate-d365-journey.py` and adapt slide builders |
| Read content | `python -m markitdown <deck>.pptx` |
| Render for QA | PowerPoint COM (§6.1) or `soffice + pdftoppm` (§6.2) |
| Inspect quality | Apply §6.3 checklist to every slide |
| Pick a layout | §4 cheat-sheet (Blank = 66 for content) |
| Pick a pattern | §5 standard patterns — vary across the deck |
| Fix overflow | §8 failure-mode table |
| Done? | Only after §6.4 + §6.5 + §10 step 11 |

---

> **One last reminder**: a PowerPoint deck is judged on its weakest slide.
> Spend more time on QA than on generation. The Anthropic skill says it best:
> *"Approach QA as a bug hunt, not a confirmation step."*
