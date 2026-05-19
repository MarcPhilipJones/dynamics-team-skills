---
name: marcs-powerpoint-creator-fluent
description: >
  Use when Marc asks to "build a Fluent 2 deck", "create a Microsoft Dynamics 365
  presentation", "generate a PowerPoint with the Microsoft template", or any
  request invoking "Marc's PowerPoint Creator". Two-phase workflow: Phase 1
  generates the deck headlessly with Python (`python-pptx`) and self-iterates at
  least three times against the Fluent 2 / boardroom-readability rules; Phase 2
  generates per-slide thumbnails via PptMcp and presents a review table for Marc
  to mark up, then applies COM-based refinements only on the slides Marc
  selects.
version: 1.0.0
author: Marc
tags:
  - powerpoint
  - pptx
  - fluent2
  - dynamics-365
  - python-pptx
  - pptmcp
  - presentation
  - two-phase
---

# Marc's PowerPoint Creator — Microsoft Fluent Design

> **Trigger**: "Marc's PowerPoint Creator", "Fluent 2 deck", "build a Microsoft Dynamics 365 deck", any pptx build that should follow Microsoft Fluent 2 + the official D365 template.

This skill produces boardroom-grade Microsoft Dynamics 365 / Fluent 2 decks in
two clearly separated phases. Phase 1 is **fast, headless, re-runnable Python**.
Phase 2 is **surgical COM polish** on the slides Marc explicitly chooses, after
reviewing thumbnails. Do not collapse the phases. Do not skip intake.

> **Golden rule**: Phase 1 must self-iterate at least three times before
> thumbnails are generated. Phase 2 only ever modifies slides Marc has called
> out by number with specific instructions.

---

## When to use this skill vs. `general-elite-powerpoint`

| Situation | Use |
|---|---|
| Marc explicitly invokes "Marc's PowerPoint Creator" / Fluent 2 / D365 template build with the two-phase flow | **This skill** |
| Generic deck work, restyling, reading a pptx, or non-Fluent branding | `general/elite-powerpoint/SKILL.md` |
| Live-demo build where Marc wants to watch PowerPoint construct slides on screen | `general/elite-powerpoint` (Pattern A) |

Both skills share the same Fluent 2 vocabulary; this one is the structured
"intake → Python pipeline → thumbnail review → targeted COM polish" recipe.

---

## Prerequisites & environment check (run BEFORE intake)

Before asking Marc anything, verify the environment. Report any gaps before
starting and offer to install.

### 1. Python availability

```powershell
python --version
```

Required: Python 3.10+ (3.11 or 3.12 preferred).

If missing, recommend:
```powershell
winget install Python.Python.3.12
```

### 2. Required Python packages

Check with:
```powershell
python -c "import pptx, PIL, requests, lxml; print('ok')"
```

If any are missing, recommend (using the workspace `.venv` already active):
```powershell
pip install python-pptx pillow requests lxml beautifulsoup4
```

Pin versions if Marc asks; otherwise stay current.

### 3. PptMcp (Phase 2 only — confirm available, do not install yet)

PptMcp is configured in `.vscode/mcp.json` as `pptmcp`. Confirm via a quick
`mcp_pptmcp_file` open/close test only when Phase 2 starts — not now. PptMcp
requires Windows + PowerPoint installed and **all .pptx files closed**.

Source repo (reference only — do not clone): `trsdn/mcp-server-ppt`.

### 4. Template discovery

**Default template** (use this if Marc does not specify an alternative):

```
skills/powerpoint/marcs-powerpoint-creator-fluent/D365Template.pptx
```

Resolution order:
1. If Marc supplies a path or link in intake, use that.
2. Otherwise, use the default above (`D365Template.pptx` next to this `SKILL.md`).
3. Fall back to scanning `presentations/themes/` only if the default file is missing.
4. If nothing is found, ask Marc to provide a path.

Confirm the chosen path with Marc in one line before starting Phase 1.

### 5. Output folder

Default output root: `presentations/<deck-name>/` (slugified). Files written:

```
presentations/<deck-name>/
  <deck-name>.pptx              ← Phase 1 output (overwritten each iteration)
  validation-report.md          ← Phase 1 self-check report
  thumbnails/slide-01.png ...   ← Phase 2 thumbnails
  review-table.md               ← Phase 2 review table (also rendered in chat)
  build_deck.py                 ← re-runnable Python script
  deck_config.py                ← intake answers as Python data
```

---

## Mandatory intake (ALL 7 questions — do not skip)

Ask all of the following before generating anything. Sensible defaults are
acceptable only if Marc explicitly says "use defaults".

1. **Template** — link or local path to the Microsoft Dynamics 365 PowerPoint
   template. Default: `skills/powerpoint/marcs-powerpoint-creator-fluent/D365Template.pptx` (alongside this skill). Falls back to scanning `presentations/themes/` if missing.
2. **Image source directory** — local folder containing approved images,
   screenshots, logos. Do **not** generate images.
3. **Stock image permission** — may Unsplash or Pexels be used for hero / large
   imagery? Default: no.
4. **Agenda** — the agenda items (always rendered as a simple vertical list,
   never cards).
5. **Demo alignment** — scenario, personas, business process flow, products
   shown, key moments, slides → demo → recap transitions.
6. **Win themes** — strategic messages to weave through (sparingly).
7. **Audience & meeting context** — seniority, industry, technical/exec
   balance, duration, live-demo yes/no, post-share yes/no.

Do not start Phase 1 until intake is complete or explicit defaults are agreed.

---

## Phase 1 — Python build with self-iteration (≥3 passes)

Phase 1 is **headless** (`python-pptx`, no PowerPoint UI). It produces a
re-runnable script and runs at least three internal iteration passes, each
checking itself before moving on. Marc is **not** asked for feedback between
iterations 1, 2, and 3 — the script self-validates. Marc reviews only after
Phase 2 thumbnails are produced.

### Source-of-truth rules (carried forward from the original spec)

These rules govern every iteration. Treat as non-negotiable.

- **Format**: 16:9, `prs.slide_width = Inches(13.333)`, `prs.slide_height = Inches(7.5)`.
- **Safe margins**: 0.55" left/right, 0.35" top/bottom.
- **Template**: load Marc's template via `Presentation(template_path)`; reuse layouts; do not fight the master.
- **Fluent 2**: clean layouts, strong hierarchy, generous whitespace, calm typography, minimal decoration, subtle depth, rounded corners where the template allows.
- **British English**: organisation, prioritise, colour, centre, behaviour, fulfil, travelling, licence (n)/license (v). UK dates (`1 May 2026`), `£` for sterling. Apply via post-processing dictionary; never alter product names, URLs, code, filenames, or quoted source.
- **Microsoft terminology**: Microsoft Dynamics 365, Dynamics 365 Customer Service / Contact Centre / Sales / Field Service / Customer Insights (- Journeys where journeys-specific), Microsoft Copilot, Copilot Studio (not Power Virtual Agents), Power Platform / Apps / Automate / BI, Microsoft Teams, Microsoft Teams Phone, Azure Communication Services, Microsoft Dataverse, Microsoft Entra ID (not Azure AD), Microsoft Graph. Full name on first mention, short form after. Never mix old and new on the same slide.
- **Narrative flow**: title → context → agenda (list) → challenge → impact → Microsoft solution → demo set-up → persona journey → capability summary → business value → adoption → next steps → close.
- **Boardroom readability**: title 28–36 pt, body 18–24 pt, never below 14 pt. ≤5 bullets, ≤10 words each, ≤65 words per slide.
- **Accessibility**: alt text on meaningful images, decorative flag where possible, body contrast ≥ 4.5:1, large text ≥ 3:1, prefer ≥ 5.5:1 for projection.
- **Images**: approved directory only; Unsplash/Pexels only if permission granted; preserve aspect ratio; never stretch; subtle overlay when text sits on imagery; never generate images.
- **Speaker notes**: 2–4 short British-English sentences on problem, solution, demo, value, next-steps slides. ≤450 chars. Skip purely visual dividers.
- **Agenda is always a vertical list.** No cards. No tiles. No circles. ≤7 items.

### Iteration model — three internal passes

Implement as three explicit pipeline stages in `build_deck.py`. Each stage
ends with a self-check; failures are auto-fixed where deterministic and
logged where not.

#### Iteration 1 — Structure
- Storyline, slide titles, agenda, demo flow, layout assignments.
- Self-check: agenda present and list-form; one message per slide; demo set-up + recap slides exist; titles are points (not labels).

#### Iteration 2 — Design
- Apply template theme; insert approved imagery only; align layouts; consistent typography and spacing.
- Self-check: every slide uses a template layout (no rogue text-boxes where placeholders exist); image aspect ratios preserved; agenda still list-form.

#### Iteration 3 — Polish & QA
- British English pass; Microsoft terminology pass; speaker notes added; accessibility + contrast checks; density flags.
- Self-check: full validation report (`validation-report.md`) generated. Blocking issues halt the run; warnings are logged.

### Validation report (Phase 1 deliverable)

Always written to `presentations/<deck-name>/validation-report.md` with sections:
Summary · Slide size · Accessibility · Contrast · Text density · British English · Microsoft terminology · Images & attribution · Speaker notes · Manual review items.

Blocking issues (must be fixed before Phase 2):
- Wrong slide ratio
- Missing template
- Missing agenda or non-list agenda
- Light text on light background
- Stock images used without permission
- Deprecated Microsoft product names on final slides
- Missing speaker notes on relevant slides

Suggested thresholds:

```python
MAX_WORDS_PER_SLIDE = 65
MAX_BULLETS_PER_SLIDE = 5
MAX_MAJOR_OBJECTS_PER_SLIDE = 7
MIN_BODY_FONT_PT = 18
MIN_ANY_FONT_PT = 14
MAX_NOTES_CHARS = 450
MIN_BODY_CONTRAST = 4.5
MIN_LARGE_TEXT_CONTRAST = 3.0
PREFERRED_PROJECTOR_CONTRAST = 5.5
```

### Recommended file layout for Phase 1

```
presentations/<deck-name>/
  build_deck.py          ← orchestrator (load template → 3 iterations → save)
  deck_config.py         ← intake answers
  validators.py          ← contrast, density, bounds, agenda-shape checks
  british_english.py     ← UK_REPLACEMENTS dictionary + apply()
  terminology.py         ← MS terminology check + replace
  <deck-name>.pptx       ← output
  validation-report.md   ← output
```

Keep each file < ~200 lines. Create one file at a time. Validate each step
before moving on (anti-stalling pattern from `copilot-instructions.md`).

### Phase 1 exit criteria

- All three iterations complete.
- `validation-report.md` written.
- Zero blocking issues.
- `<deck-name>.pptx` saved successfully.
- All warnings reported to chat with the path to the report.

Only when these criteria are met does Phase 2 begin.

---

## Phase 2 — Thumbnails, review table, targeted COM refinement

Phase 2 uses **PptMcp** (configured MCP server, COM-based, Windows + PowerPoint).
The repository `trsdn/mcp-server-ppt` is the upstream — do not clone or rebuild;
the workspace's `pptmcp` MCP server is already configured.

### Pre-flight for PptMcp

- All `.pptx` files (including the Phase 1 output) must be **closed in PowerPoint** — COM needs exclusive access.
- Open the deck via `mcp_pptmcp_file` with `action: open`, `show: false` (headless build, preview at the end — see `tools-pptmcp.md` performance findings).
- Capture and reuse the returned `session_id` for every subsequent PptMcp call.

### Step 2a — Generate thumbnails

For every slide in the deck, generate a thumbnail PNG into
`presentations/<deck-name>/thumbnails/slide-NN.png`. Use `mcp_pptmcp_slide`
get-thumbnail per slide. Embed thumbnails inline in the chat review table
where the surface allows.

### Step 2b — Build the review table

Produce a Markdown table with **exactly four columns**:

| Slide # | Slide Purpose | What it does | Suggested COM refinement |
|---|---|---|---|

For each slide:
- **Slide #** — 1-indexed.
- **Slide Purpose** — the narrative role (Title / Agenda / Challenge / Solution / Demo set-up / Persona journey / Value / Next steps / Close, etc.).
- **What it does** — one-line factual description of current content.
- **Suggested COM refinement** — concrete, actionable polish only achievable
  via COM (e.g. "add subtle shadow to capability cards", "convert hand-laid
  arrows to SmartArt process", "align persona icons to a 12-column grid",
  "apply Fluent 2 accent gradient to the divider band", "tighten leading on
  the value-pillar headers"). If the slide is already strong, write
  "No change recommended".

Output the table:
1. **Inline in chat** for Marc to read.
2. **Saved to `presentations/<deck-name>/review-table.md`** for the record.

### Step 2c — Wait for Marc

Stop. Marc reviews the table and tells you which slide numbers to refine and
exactly what to change. Do not pre-emptively pick rows. Do not start COM
operations until Marc gives slide numbers + instructions.

### Step 2d — Apply COM refinements (only on Marc-specified slides)

For each slide Marc nominated:
1. Use the existing PptMcp `session_id`.
2. Apply the change Marc specified using the appropriate `mcp_pptmcp_*` tool
   (`shape`, `text`, `image`, `shapealign`, `smartart`, `animation`,
   `placeholder`, `chart`, `slidetable`, etc.).
3. After the slide is done, regenerate that slide's thumbnail and show it
   back so Marc can confirm.
4. Save once all nominated slides are processed (`mcp_pptmcp_file` with
   `action: save`).
5. Close PowerPoint via `mcp_pptmcp_file` with `action: close, save: true`
   only when Marc confirms he is fully done.

### What Phase 2 must NOT do

- Do not regenerate slides Marc did not select.
- Do not restructure narrative or rewrite copy unless Marc asks.
- Do not re-run Phase 1 — if Marc wants structural changes, return to Phase 1
  and re-run all three iterations.
- Do not leave PowerPoint open with unsaved changes.

---

## Common mistakes & warnings

- **Skipping intake** — even one missing answer leads to rework. Ask all 7.
- **Generating images** — never. Approved directory or (with permission)
  Unsplash/Pexels only.
- **Cards for the agenda** — always a list. Always.
- **Mixing old/new product names on one slide** — choose one register per slide.
- **Pasting Power Fx-style strings from a browser** — the British English pass
  and quoted source rules can be broken by invisible Unicode. Type, don't paste.
- **Running PptMcp with the deck open in PowerPoint** — COM will fail. Close
  the file first.
- **Per-shape thumbnails during Phase 2 polish** — slow. Take thumbnails only
  when a slide's refinements are complete.
- **Letting Phase 1 stop after one iteration** — the spec mandates ≥3 internal
  passes. Self-validate, don't ask Marc between them.
- **Force-pushing the build** — never bypass approval; Phase 2 changes only
  the slides Marc explicitly nominates.

---

## Learnings from real builds (gotchas to bake into every Phase 1 script)

These are confirmed gotchas hit on first run and must be coded around from
the start of every new deck — do not rediscover them.

### 1. Templates ship with sample slides — purge them properly

`Presentation(template_path)` exposes the template's existing slides. Removing
them from `prs.slides._sldIdLst` only is **not enough** — the slide parts and
relationships remain in the package, and saving produces a stream of:

```
UserWarning: Duplicate name: 'ppt/slides/slideN.xml'
```

The deck still opens, but the file is malformed. Always purge with both the
sldId entry AND the relationship:

```python
def _purge_template_slides(prs):
    sldIdLst = prs.slides._sldIdLst
    rId_attr = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id"
    entries = [(sldId, sldId.get(rId_attr)) for sldId in list(sldIdLst)]
    for sldId, rId in entries:
        try:
            prs.part.drop_rel(rId)
        except Exception:
            pass
        sldIdLst.remove(sldId)
```

Call it immediately after `Presentation(...)` and before adding any slides.

### 2. Windows console is cp1252 — `print` will crash on Unicode arrows

`print("Saved → file.pptx")` raises `UnicodeEncodeError` on the default
PowerShell terminal. Fixes (use both):

- Stick to ASCII (`->`, `==>`) in `print` statements.
- At the top of `build_deck.py`, set:

```python
import sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.stderr.reconfigure(encoding="utf-8", errors="replace")
```

Or run with `$env:PYTHONIOENCODING='utf-8'` before invocation.

### 3. Agenda density check needs an exemption

The default `MAX_WORDS_PER_SLIDE = 65` will flag a real workshop agenda
(10–12 items × time + label easily exceeds 65). The agenda is a list — that
is the point. Relax the rule for `purpose == "agenda"`:

```python
if spec.purpose == "agenda":
    threshold = MAX_WORDS_PER_SLIDE * 3  # times + labels add up fast
else:
    threshold = MAX_WORDS_PER_SLIDE
```

Same applies to dividers with subtitles and "next steps" recap slides.

### 4. Working directory drift in chained terminal commands

`cd subdir; python build_deck.py` then `cd subdir; …` again lands in
`subdir/subdir`. Solution: use **absolute paths in `deck_config.py`** for
`PROJECT_DIR`, `TEMPLATE_PATH`, `OUTPUT_PPTX`, and **all image paths**, so
the pipeline is reproducible from any cwd. Already encoded in the template;
keep it that way.

### 5. Background images on title / divider slides need an overlay

`python-pptx` cannot set fill alpha on a shape directly. To make text legible
over a hero image, do not bother trying to make a transparent overlay — use a
**half-canvas solid coloured band** (e.g. left 7.5" Fluent neutral-dark
rectangle) and place text on the band. This is what the working build does
and it survives any image content.

### 6. Always set `tf.word_wrap = True`

Untouched text frames in template layouts often default to no-wrap, which
silently truncates bullets at the right edge. Set `word_wrap = True` on every
text frame the script writes to.

### 7. Don't trust placeholders to exist

Template layouts vary. Code defensively: try the placeholder by `idx == 0`
for the title; fall back to a manually positioned `add_textbox` if missing.
The same goes for "Title and Content" — fall back to "Title and content" or
the second layout in the deck.

### 8. Iteration 3 must reapply UK + terminology

Even though every `_set_text` / `_set_bullets` call goes through
`_normalise_text`, runs that get appended later (or appear via placeholders)
can slip through. The iteration 3 sweep that walks every shape and every
notes_text_frame is **not optional** — it is the safety net.

### 9. Validation thresholds should be data-driven, not hard-coded in checks

When density / font / notes thresholds change, the source of truth is
`deck_config.py`. `validators.py` imports them by name. Don't inline numbers
in the validator — Marc will tune them per deck.

### 10. Final Phase 1 sign-off line

Always end the Phase 1 run with a single chat line of the form:

> *Phase 1 complete: N slides, X blocking issues, Y warnings. Deck at `<path>`. Validation report at `<path>`. Ready to move to Phase 2 when you confirm.*

Marc reads this and decides. Do not start Phase 2 automatically.

### 11. "Boring deck" is the default failure mode — bake Fluent 2 chrome in from slide 1

The first build hit zero blocking issues but felt flat: text-only slides, no
chips, no accent rules, default placeholder typography. Fluent 2 *is a visual
system*; treat it like one from iteration 1, not as decoration added later.
Every slide should include at minimum:

- A **soft canvas** (Fluent neutral background `#FAF9F8`, drawn as a
  send-to-back rectangle) — never pure white.
- A **section pill chip** in tinted brand / section colour at the top
  (`MSO_SHAPE.ROUNDED_RECTANGLE` with `adjustments[0] = 0.5` for full
  capsule), uppercased label, 10–11 pt, bold.
- A **bold 32 pt title** in Fluent neutral foreground `#201F1E`.
- A **short coloured accent bar** under the title (~0.7" × 0.05") in the
  section accent colour.
- A **white card with 0.75 pt `#E1DFDD` stroke** wrapping the body content
  (rounded `adjustments[0] ≈ 0.04`). This is the single biggest visual lift.
- **Footer + page number** in 10 pt `#605E5C` (tag with `name = "ui-…"`).
- **Bullet dots** as small brand-blue `●` glyphs prefixed in the run, not
  the default tiny black dots.

Title and divider slides must use a **half-bleed hero image** (full-height,
~7" wide on one side) with a Fluent neutral panel on the other side carrying
the chip + heading. Plain coloured backgrounds look 2010.

### 12. Sectioned colour system is mandatory — define `SECTION_COLOURS` up front

Every slide carries a `section` field; the build script looks up
`SECTION_COLOURS[section]` to get `(accent_rgb, tint_rgb, text_rgb)`. This
makes pills, accent bars, and dividers self-colour from the agenda. Use
brand blue as the default, plus 2–3 accent hues (e.g. green `#107C10`,
purple `#5F339E`, burgundy `#A51B26`) and a neutral grey for breaks/lunch.
The agenda slide picks the same accent per row, so the deck visually ties
together.

### 13. Agenda slide — capsule rows beat plain text every time

The reference design Marc approved is a stack of 12 horizontally laid-out
capsule cards: `[time | accent bar | title | sublabel right]`. Build it as:

- Top pill `AGENDA · {DATE.upper()}`.
- 36 pt heading "Agenda for the day".
- 12–14 pt sub-heading line summarising scope.
- One rounded card per row (`adjustments[0] = 0.5` for capsule), break/lunch
  rows fill `#F3F2F1` and use muted text.
- Inside each card: time column (1.4"), 6 pt vertical accent bar coloured
  per section, bold title text (vertically centred), right-aligned sublabel
  in muted grey.

Treat this layout as the default whenever agenda has 8+ items.

### 14. UI chrome shapes need a `name` prefix so the validator skips them

Pills (11 pt), footers (10 pt), page numbers (10 pt), agenda time/sublabel
boxes (12–14 pt) are intentionally below `MIN_BODY_FONT_PT` — they're UI
chrome, not body copy. Without help, the validator screams 100+ `font-tiny`
warnings every build. Tag every chrome shape:

```python
pill.name = "ui-pill"
footer.name = "ui-footer"
pagenum.name = "ui-pagenum"
agenda_card.name = "ui-agenda-row"
```

Then in `validators.py`, skip both font checks and density-objects on shapes
whose `name` starts with `ui-`. That is the only clean way to keep agenda
slides (~65 chrome shapes) from poisoning the report.

### 15. `create_file` cannot overwrite — plan rewrites accordingly

When the redesign requires a substantially new `build_deck.py`, the
`create_file` tool refuses to clobber. Either run `Remove-Item` first, or
do one large `replace_string_in_file`. Don't waste a turn discovering this.

### 16. Strip layout placeholders before drawing

Calling `_strip_layout_placeholders(slide)` (remove every shape inside
`slide.placeholders`) before adding your own shapes prevents inherited
title/body placeholders from showing through and stops "phantom" text
appearing behind hero panels.

### 17. Images get squashed when width AND height are both fixed — use cover-fit

The single biggest visual quality issue from the v2 build: `add_picture(path,
left, top, width=W, height=H)` forces the image into the rectangle and
distorts it. Wide landscape product photography (e.g. automotive exteriors,
interiors, architectural shots) rendered into a ~5.5" × 5.0" rectangle looks
visibly squashed.

**Three fixes, in order of preference:**

1. **Cover-fit with `_cover_picture()` helper.** Read the source image
   dimensions with `Pillow`, compute the scale factor that *covers* the
   target rectangle, place the picture with one fixed dimension only, then
   crop the overflow using `pic.crop_left/right/top/bottom` (each is a
   fraction 0.0–1.0 of the original). This preserves aspect ratio and
   fills the frame.

2. **Aspect-aware target rectangles.** For landscape source images, design
   the slot landscape (e.g. ~6.4" × 3.6"); for portrait sources, portrait.
   Persona "image-right" slots that are near-square will always squash a
   3:2 photo.

3. **Half-bleed hero panels.** When the source is hero-grade (title,
   divider, close), use a full-height column (~6"–7" wide × 7.5" tall)
   and crop the sides — looks dramatic, never squashed.

Required helper to add to every Phase 1 build:

```python
from PIL import Image

def _cover_picture(slide, path, left, top, width, height):
    """Fill (left,top,width,height) with image, preserving aspect ratio.
    Crops overflow on the long axis so the image always covers the slot."""
    if not path or not Path(path).exists():
        return None
    with Image.open(path) as im:
        src_w, src_h = im.size
    target_ratio = width / height
    src_ratio = src_w / src_h
    pic = slide.shapes.add_picture(str(path), left, top, width=width, height=height)
    # Counter-distortion via crop fractions
    if src_ratio > target_ratio:
        # Source wider than target — crop left/right
        scale = target_ratio / src_ratio
        crop = (1.0 - scale) / 2.0
        pic.crop_left = crop
        pic.crop_right = crop
    elif src_ratio < target_ratio:
        scale = src_ratio / target_ratio
        crop = (1.0 - scale) / 2.0
        pic.crop_top = crop
        pic.crop_bottom = crop
    return pic
```

Use `_cover_picture` everywhere `_safe_picture` was used for a fixed-size
rectangle. Keep `_safe_picture` only for hero/full-bleed panels where the
source already matches the target ratio.

### 18. Section pill must render the section's display label, not the key

Slide 2 (section="Open") rendered an empty pill because "Open" tinted blue
on blue tint reads as invisible at 11 pt. Two fixes:

- Map section keys to display labels (e.g. `"Open" → "OPENING"`) so the chip
  always carries a recognisable word.
- Or skip the pill entirely on the welcome slide and use `INTRODUCTION` /
  `WORKSHOP` as a deck-level chip on the first non-title slide.

### 19. Phase 2 review must inspect actual thumbnails, not assume Phase 1 is OK

Phase 1 reports "0 blocking issues" yet image distortion is invisible to
the validator. Phase 2 must visually inspect a representative sample
(title, agenda, every persona, every divider, hero close) and surface
issues like squashing, empty chips, weak hierarchy, low contrast — none
of which can be detected by python-pptx alone.

### 20. Circular portraits via Pillow alpha mask + BytesIO

Persona slides land 10x harder with a circular portrait than a square one.
`python-pptx` has no native circle-crop, so do it in Pillow and add the
result as a PNG from memory. Pattern:

```python
from PIL import Image, ImageDraw
from io import BytesIO

def _circle_portrait(slide, path, cx, cy, diameter):
    with Image.open(path) as im:
        im = im.convert("RGBA")
        # square-crop centred
        s = min(im.size); l = (im.width-s)//2; t = (im.height-s)//2
        im = im.crop((l, t, l+s, t+s)).resize((1024, 1024), Image.LANCZOS)
        mask = Image.new("L", im.size, 0)
        ImageDraw.Draw(mask).ellipse((0, 0, *im.size), fill=255)
        im.putalpha(mask)
        buf = BytesIO(); im.save(buf, "PNG"); buf.seek(0)
    r = diameter / 2
    pic = slide.shapes.add_picture(buf, cx - r, cy - r, diameter, diameter)
    # Decorative ring 0.04" outside, brand-tint stroke, sent to back
    return pic
```

Add a thin oval ring (4 pt brand-tint stroke) just outside the circle and
send it to back for a polished portrait frame.

### 21. NEVER use `slide.shapes.add_connector(1, ...)` — it corrupts files

Symptom: `python-pptx` saves successfully, but PowerPoint refuses to open
with errors `0x80CB4404` or `0x80070570` ("file or directory is corrupted").
Bisect by saving each custom layout in isolation; the offending one will be
the only standalone file PowerPoint won't open.

**Fix:** for any diagonal line (e.g. a strike-through across a logo tile),
use a thin rotated `MSO_SHAPE.RECTANGLE` instead:

```python
import math
dx, dy = x2 - x1, y2 - y1
length = int(math.hypot(dx, dy))
angle = math.degrees(math.atan2(dy, dx))
strike = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE,
    x1, y1 - thickness//2, length, thickness)
strike.rotation = angle
```

`add_connector` produces a malformed `cxnSp` element under certain shape
combinations. Avoid it entirely — rotated rectangles cover every diagonal
use case (strike-throughs, dividers, callout lines).

### 22. `_purge_template_slides` must drop parts AND rels AND sldId

Templates ship with sample slides. Just removing entries from
`prs.slides._sldIdLst` leaves the underlying parts in the package, which
produces zip "duplicate filename" warnings and (worst case) prevents
PowerPoint from opening the file. Full purge:

```python
def _purge_template_slides(prs):
    pres_part = prs.part
    rels = pres_part.rels
    sldIdLst = prs.slides._sldIdLst
    for sldId in list(sldIdLst):
        rId = sldId.get(qn("r:id"))
        rel = rels.get(rId)
        if rel is not None:
            slide_part = rel.target_part
            try:
                del pres_part.package._parts[slide_part.partname]
            except KeyError:
                pass
            try:
                rels.pop(rId)  # NB: single-arg only — pop(rId, None) raises TypeError
            except (KeyError, TypeError):
                pass
        sldIdLst.remove(sldId)
```

`_Relationships.pop` only accepts one argument. Wrap it in
`try/except (KeyError, TypeError)`.

### 23. Stat tiles read better side-by-side when the card is wide

A "9.4 / Brand advocacy score" tile stacked vertically (value above
caption) wastes horizontal space and the tiny caption gets buried.
Conditional layout:

```python
if width >= Inches(3.5):
    # value 56pt left | caption 14pt right
else:
    # value 48pt top  / caption 11pt below
```

Also: when a stat tile sits on a persona card next to a chip grid, pin it
to the bottom as a **full-width strip** under the grid — never let it
share a column with chips, or they will overlap on long captions.

### 24. PptMcp allows only one open session at a time

Always `mcp_pptmcp_file action=close` before the next `open`. Forgetting
this strands the previous session and the second open silently fails.
Pattern: open → operate → close, every time.

### 25. Headless thumbnail loop for self-review

Standard self-review cycle (no PowerPoint window required):

1. `python build_deck.py` → confirm "blocking issues: 0".
2. `mcp_pptmcp_file open` → `mcp_pptmcp_export action=all-slides-to-images
   destination_directory=thumbnails-vN width=1280 height=720` → close.
3. `view_image` on title, agenda, every persona, each divider, every
   custom layout, and the close slide.
4. Apply targeted Python edits → loop from step 1.

Do not skip the rebuild between edits and the next thumbnail export, or
you'll review stale PNGs and miss your own fixes.

### 26. Replace bullet-list slides with structured custom layouts

When slide content is "just bullets", convert to a richer layout. Three
proven patterns (all built and shipped on a real automotive-OEM customer
deck):

**`value-cards` (2×2 capability grid)**
- Use for any 4-bullet capability/benefit/feature list.
- Each card: top accent strip (0.10") in section colour, large `f"{i+1:02d}"`
  numeral (40 pt bold) sitting inside a tinted disc (`MSO_SHAPE.OVAL`,
  `_tint_for(accent)` fill, no line, diameter ≈ 1.10"), single bold 18 pt
  headline `MSO_ANCHOR.MIDDLE` to the right of the disc.
- Card_w = (avail_w - gap)/2; card_h = (avail_h - gap)/2.
- Per-card colour cycle: `[F2_BRAND_PRIMARY, F2_PURPLE, F2_GREEN, F2_BURGUNDY]`.
- Add a `_tint_for(rgb)` helper mapping each primary to its tint constant.

**`journey-road` (milestone path, replaces step-1/step-2/step-3 blocks)**
- Pill-shaped road: `MSO_SHAPE.ROUNDED_RECTANGLE` with `adjustments[0]=0.5`,
  fill F2_BRAND_PRIMARY, full width inside safe area, `road_h = 0.45"`.
- Dashed centre line: repeat short white capsules (0.35" wide × 0.05" tall,
  0.30" gaps) across the road centre.
- N numbered pins on the road (oval, white 2.5 pt outline, per-pin colour
  cycling brand/purple/green/burgundy/shade), diameter ≈ 0.95".
- Cards alternate above (i%2==0) and below the road; **guard the connector
  rectangle** with `if connector_h > Emu(9525):` — negative-height shapes
  corrupt the file and PowerPoint refuses to open.
- Optional soft horizontal back-plate (`F2_NEUTRAL_BG_2`) behind the road,
  sent to back, grounds the metaphor visually.
- START / FINISH labels (10 pt FG_3) at road ends; LIVE DEMO badge top-right
  if appropriate.

**`meet-personas` (two-column cast intro)**
- Use ONCE early in the deck to introduce two personas side-by-side.
- Pill, 32 pt title, accent bar, then a **compact** lead-line (custom
  textbox 17 pt × 0.55" tall — do NOT use the full `_lead_line` helper, it's
  1.0" tall and pushes columns over the footer).
- Two columns share a vertical divider (19050 EMU rectangle in
  `F2_NEUTRAL_FG_3`, lighter than `_STROKE_1`). Soft tinted column
  backgrounds (`MSO_SHAPE.ROUNDED_RECTANGLE`, `adjustments[0]=0.04`,
  send-to-back, fill = persona's tint colour) anchor each side.
- Per-column: stage label (10 pt bold centred) → circular portrait diameter
  2.10" with **coloured ring** in persona's deep colour (e.g. Alex=brand
  blue, James=purple) → name 24 pt → tagline 13 pt FG_2 → 3 chips → italic
  goal line 12 pt FG_2.

**Consistency rule (critical):** Within one layout, all items must share
the same structure. Don't conditionally split one card on em-dash if the
others have no em-dash — strip the partition logic and use single-headline
text for every card.

### 27. Iteration discipline — "at least 3 iterations" means visible fixes

Each iteration must address something concrete and visible, not subjective.
Per pass: build → export thumbnails → `view_image` → list real problems
(text wrap, overflow, inconsistency, file corruption, weak hierarchy) →
fix → rebuild. Don't stop at "looks fine"; push for micro-polish (tinted
discs, soft back-plates, lighter dividers, depth cues). When the user says
"only show me the final output", do NOT post intermediate thumbnails — just
deliver the final markdown link with a one-line summary.

---

## Definition of done

Deck is complete only when **all** of the following are true:

- Marc's template was used (no blank-default fallback).
- 16:9 throughout.
- Agenda is a simple vertical list.
- Demo alignment reflected in narrative.
- Approved imagery only.
- British English applied.
- Current Microsoft product names applied.
- Relevant slides include succinct speaker notes.
- Accessibility + contrast checks pass (or exceptions documented).
- Phase 1 validation report written with zero blocking issues.
- Phase 2 thumbnails generated.
- Phase 2 review table delivered (chat **and** file).
- Phase 2 COM refinements applied only on Marc-nominated slides.
- Final `.pptx` saved and PowerPoint closed cleanly.

---

## Key takeaway

> Phase 1 is fast, headless, self-checking Python that nails structure,
> language, accessibility, and Fluent 2 layout in three iterations. Phase 2
> is surgical: thumbnails → review table → wait for Marc → apply COM polish
> only on the slides he calls out. Never collapse the phases. Never act on
> Phase 2 without Marc's row-by-row direction.
