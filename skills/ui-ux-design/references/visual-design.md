# Visual design reference

Concrete values and patterns behind the rules in `SKILL.md`. Treat them as
defaults: an existing design system in the product always wins.

## Spacing scale (4 px base unit; prefer multiples of 8 for layout gaps)

| Token    | px  | Typical use                                 |
| -------- | --- | ------------------------------------------- |
| space-1  | 4   | icon ↔ label, tight inline gaps             |
| space-2  | 8   | items inside a control, chip padding        |
| space-3  | 12  | form label ↔ input                          |
| space-4  | 16  | default padding, gap between related fields |
| space-6  | 24  | card padding, gap between field groups      |
| space-8  | 32  | between sections inside a page              |
| space-12 | 48  | between major page regions                  |
| space-16 | 64  | hero / page-level breathing room            |

Rule of thumb: the gap _between_ groups should be at least 2× the gap _within_ a
group, or the grouping won't read.

## Type scale (16 px base, ratio 1.25 upward; 14 and 12 are pragmatic small steps)

| Token | px  | Line-height | Use                         |
| ----- | --- | ----------- | --------------------------- |
| xs    | 12  | 1.4         | captions, meta (sparingly)  |
| sm    | 14  | 1.45        | secondary text, table cells |
| base  | 16  | 1.5         | body, inputs, buttons       |
| lg    | 20  | 1.4         | lead text, card titles      |
| xl    | 25  | 1.25        | section headings            |
| 2xl   | 31  | 1.2         | page title                  |
| 3xl   | 39  | 1.1         | hero / display              |

Weights: 400 body, 500–600 labels and emphasis, 700 headings. Avoid using more
than three weights. `lg` is used for lead text as well as titles, so it keeps
body-like leading. Headings from `xl` up use 1.1–1.3.

Dense, data-heavy tools for experts (from the brief) may use a 14 px base. Never
go below 12 px for anything users need to read.

## Color tokens (structure, not a palette)

```
--color-bg            page background
--color-surface       cards, panels
--color-surface-2     raised / hovered surface
--color-border        dividers, input borders (≥ 3:1 vs surface for inputs)
--color-text          primary text      (≥ 4.5:1 vs bg and surface)
--color-text-muted    secondary text    (still ≥ 4.5:1)
--color-primary       interactive + primary CTA
--color-on-primary    text on primary   (≥ 4.5:1 vs primary)
--color-focus         focus ring        (≥ 3:1 vs adjacent colors)
--color-success / -warning / -danger / -info   (+ matching on-* and subtle bg)
```

If dark mode is in scope, define every token for both light and dark. In dark mode, avoid pure black (#000)
backgrounds and pure white body text; use a dark grey surface and slightly
dimmed text to reduce glare, and lower saturation on large colored areas.

Muted grey text is the most common contrast failure, so check it first. Compute
every pair with `scripts/contrast.py` rather than judging by eye. For example,
`#767676` on white is 4.54:1 (passes) but `#777777` is 4.48:1 (fails).

## Layout patterns

- **Content width:** `max-width: 60–70ch` (about 600–680 px at 16 px) for prose; 1200–1440 px max for app
  shells, with fluid side gutters (16 px mobile, 24–32 px desktop).
- **Grid:** 4 columns on mobile, 8 on tablet, 12 on desktop.
- **Forms:** single column, labels above inputs, primary button aligned with
  the inputs' leading edge, related fields grouped with headings.
- **Tables:** left-align text, right-align numbers, use tabular numerals,
  keep row height ≥ 40 px, and use sticky headers for long lists.
- **Dashboards:** put the single most important metric top-left, group
  related KPIs, and use consistent card heights within a row.
- **Breakpoints:** design for the content, not the device. Add a breakpoint
  where the layout breaks.

## Hierarchy toolkit

How strong each tool is depends on context. Contrast and position often
outrank weight. Rely mainly on the first four, and combine at most two on any
one element:

- Size
- Weight
- Contrast against the background (color)
- Position (top/left first in LTR)
- Whitespace around the element
- Decoration (border, shadow, background), the weakest and the noisiest

To de-emphasise something, reduce contrast or size rather than adding
decoration to everything else.

## Buttons

- **One primary** (filled, brand color) per view or section.
- **Secondary**: outlined or tonal. **Tertiary**: text-only.
- **Destructive**: danger color. Use it only for the confirming action, not
  the button that opens the dialog.
- Label buttons with verbs ("Save changes", "Delete project"), not "OK" or
  "Submit".
- Minimum height 40 px on desktop, 44–48 px on touch devices. The WCAG 2.2 AA
  floor is 24×24 px for any pointer target.

## Common mistakes → fixes

| Mistake                                           | Fix                                                                                     |
| ------------------------------------------------- | --------------------------------------------------------------------------------------- |
| Everything bold or colored, so nothing stands out | Pick one focal element; demote the rest with lighter weight or muted color              |
| Equal spacing everywhere, so groups don't read    | Tighten space within groups and widen it between them                                   |
| Borders around every element                      | Remove borders; separate with whitespace or a subtle surface change                     |
| Placeholder used as the label                     | Keep a persistent label above the input; use the placeholder only for an example format |
| Low-contrast grey text                            | Darken it to reach 4.5:1; if it still looks heavy, reduce its size instead              |
| Red/green as the only status signal               | Add an icon and text ("Failed", "Passed")                                               |
| Centred multi-line body text                      | Left-align (start-align) it                                                             |
| Several primary buttons on one view               | Keep one primary and demote the others                                                  |
| Focus outline removed for looks                   | Restyle it (2 px ring, offset, `--color-focus`) and never remove it                     |
| Designed only with ideal data                     | Mock up empty, long-text, error, loading and 1,000-row states                           |
| Sticky header covers the focused field            | Add `scroll-padding-top` equal to the header height                                     |
| Password field blocks paste                       | Allow paste and password-manager autofill (`autocomplete="current-password"`)           |
| Error shown only as a red border                  | Add error text next to the field, linked with `aria-describedby`                        |
