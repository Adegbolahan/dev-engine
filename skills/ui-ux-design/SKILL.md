---
name: ui-ux-design
description: This skill should be used when the user asks to design, redesign, mock up, wireframe, restyle, or improve the look or usability of a UI (screen, page, dashboard, form, flow) — e.g. "design a settings page", "make this dashboard look better", "redesign the signup flow", "improve the layout", "review the UX of this page", "is this accessible/usable?" — or asks for a UI/UX or visual design review. Runs a context/audience discovery step first, then applies visual design rules. Not for pure CSS bug fixes or wiring up logic.
version: 0.2.0
---

# UI/UX Design

Two parts, in order:

1. **Discovery**: establish context and audience _before_ designing anything.
2. **Visual design**: build (or review) the interface against concrete visual rules.

Design that skips discovery gets the visuals right for the wrong person. A
polished screen for an imagined user is a rewrite waiting to happen.

## Relationship to other skills

If `frontend-design` is also active, run this skill's discovery first. The
brief's **Tone** line decides how bold the aesthetic should be. `frontend-design`
owns aesthetic direction: type personality, palette character, motion. This skill
owns discovery, hierarchy, accessibility, states and the review checklist, and
those apply whatever the aesthetic.

## Part 1: Discovery (context and audience)

### Scale discovery to the request

| Request size                                                            | Discovery                                                                                                                                                 |
| ----------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Small tweak** (one component, a style fix, "make this button bigger") | Infer the brief from the request and code. Add a 1–2 line `Assumed:` note. Don't ask.                                                                     |
| **New screen, flow, or redesign**                                       | Full brief. Ask about any must-know that is still open.                                                                                                   |
| **Review of an existing UI**                                            | Infer the brief from the interface and codebase, and state assumptions at the top of the review. Ask only if the audience or job truly can't be inferred. |

### Rule

For new screens, flows and redesigns, do not produce a layout, mockup,
component or style choice until the **must-know** questions have answers.
Look for answers in this order:

1. **The request itself**: the user already said it.
2. **The codebase or existing product**: read it instead of asking. Look at
   design tokens, the component library, the CSS framework, brand colors and
   fonts, similar screens, and target platforms in config (`package.json`,
   Tailwind config, theme files, `manifest.json`, iOS/Android projects).
3. **The user**: ask only what 1 and 2 could not answer.

Ask in **one batch** with AskUserQuestion, which takes at most 4 questions.
Don't drip single questions. Put a recommended default first in each question
so the user can accept quickly. If more than 4 must-knows are open, ask the
first 4 in this priority order and default the rest:

1. Primary user and expertise (one question; put the expertise level in the options)
2. Primary job
3. Deliverable
4. Device and input
5. Fit with the existing system
6. Accessibility (default to WCAG 2.2 AA)

If the user says "just pick", or AskUserQuestion is unavailable (for example in
headless runs or as a subagent), choose sensible defaults, list them under
`Assumed:`, and proceed.

### Must-know questions (for new work, block design until answered or defaulted)

**Audience**

- **Who is the primary user?** Describe a role, not demographics:
  "warehouse staff scanning stock", "first-time buyer", "on-call SRE at 3 a.m.".
- **How expert are they, with the domain and with this product?** Novices need
  guidance and progressive disclosure. Experts need density, shortcuts and bulk
  actions. Is it used daily or once a year?
- **What accessibility needs must be met?** Default to WCAG 2.2 AA unless told
  otherwise. Ask about known needs: low vision, motor, screen readers, older
  users, low literacy, non-native language.

**Context**

- **What is the one job this screen or flow must do?** The primary task, and
  what "done" looks like. If there are several jobs, which wins when they compete?
- **Where and how is it used?**
  - Device: desktop, phone, tablet, kiosk, TV.
  - Input: mouse, touch, keyboard-only, scanner.
  - Environment: bright outdoor, noisy, one-handed, interrupted, under time pressure.
  - Connectivity.
- **What already exists that this must fit?** Design system, component library,
  brand guidelines, neighbouring screens. Is it a new look, or should it match?
- **What form should the design take?** Working code, a standalone HTML/CSS
  mock, a markdown/ASCII wireframe, or written recommendations. Default: working
  code in the existing stack if there is a codebase; otherwise a single-file
  HTML/CSS mock.

### Should-know questions (ask if cheap; otherwise default and state)

- **Business goal and success metric.** Conversion, task time, fewer support
  tickets, retention? This decides which element gets visual priority.
- **Content reality.** Real data volumes and lengths (10 rows or 10,000? names
  of 4 or 40 characters?), empty states, error states, localisation and RTL.
- **Constraints.** Tech stack, deadlines, performance budget, legal or
  regulatory copy, whether dark mode is in scope.
- **Tone.** Trustworthy and clinical, playful, premium, or utilitarian.
- **Prior art.** Products the audience already uses (Jakob's Law: match their
  expectations), and examples the user likes or dislikes.

### Discovery output

Before designing, write a short **design brief** (5–9 lines) back to the user:

```
Audience:   <primary user, expertise, frequency>
Job:        <primary task + definition of done>
Context:    <device, input, environment>
Fits into:  <design system / brand / existing screens>
Output:     <working code | HTML mock | wireframe | recommendations>
Priority:   <what must be most prominent, and why>
A11y:       <target level + specific needs>
Themes:     <light only | light + dark>
Assumed:    <every default chosen without an answer>
```

Then proceed straight away. The exception is when an `Assumed:` line covers a
must-know with large design impact, such as the audience, the job or the
deliverable. In that case, ask the user to confirm in the same message before
building.

Every later visual decision should trace back to a line in this brief. If a
decision can't, question it.

## Part 2: Visual design

Apply these rules when building, and use them as the checklist when reviewing.
Read `references/visual-design.md` before choosing concrete values (spacing,
type, tokens) or before running a review, unless the product's design system
already defines those values.

### 1. Hierarchy: one thing first

- Each screen has **one primary action** and **one focal point**, chosen from
  the brief's _Priority_ line. Everything else is visibly secondary.
- Create rank mainly with **size, weight, contrast, and position**. Combine at
  most two; don't make everything bold _and_ colored.
- Check the focal point. If a browser or screenshot tool is available, render
  the page and inspect it, blurred if possible. Otherwise, confirm from the
  styles that the focal element is the largest, heaviest or highest-contrast
  item in its region.
- Support scanning:
  - Front-load headings, labels and links with the keywords users look for.
    F-shaped scanning is a failure mode to design against, not a layout to aim for.
  - On sparse or landing pages (Z-pattern), put key info top-left (top-right
    in RTL) and the primary CTA at the end of the scan path.
  - In forms, align the primary button with the inputs' leading edge.

### 2. Spacing and layout: rhythm and grouping

- Use a **spacing scale** with a 4 px base unit (4, 8, 12, 16, 24, 32, 48, 64).
  Prefer multiples of 8 for layout-level gaps. No one-off values.
- **Proximity communicates grouping** (Gestalt): space _within_ a group is
  smaller than space _between_ groups. Separate with whitespace rather than
  borders and boxes.
- Align everything to a **grid**, and minimise the number of distinct left edges.
- Limit the reading measure to about 45–75 characters per line. In CSS, use
  `max-width: 60–70ch` for prose.
- Design **mobile-first** when the brief says phones are in play. Content must
  reflow at 320 CSS px wide without horizontal scrolling.

### 3. Typography: readable and limited

- One typeface, or at most two (display + text). Get variation from weight and
  size, not more families.
- A **type scale** of 5–7 sizes, for example a 1.2–1.25 ratio upward from the base.
- Body text ≥ 16 px. 14 px is acceptable for dense expert tools if the brief
  says so. Never go below 12 px for anything users need to read.
- Form inputs ≥ 16 px; smaller inputs trigger auto-zoom in iOS Safari.
- Line-height about 1.4–1.6 for body text and about 1.1–1.3 for headings.
- Text must survive being resized to 200% without clipping or overlapping.
- Use sentence case for UI labels. Avoid all-caps for anything longer than a
  short label.
- Left-align body text (start-align in RTL). Centre only short, standalone lines.

### 4. Color: meaning, not decoration

- Build from tokens:
  - Neutrals dominate the UI.
  - **One** primary/brand color, reserved for interactive and primary elements.
  - Semantic colors (success, warning, danger, info), used only for status.
- **Contrast**:
  - Text ≥ 4.5:1.
  - Large text ≥ 3:1. Large means ≥ 24 px regular, or ≥ 18.66 px (14 pt) bold.
  - UI component boundaries and focus indicators ≥ 3:1 against their neighbours.
- **Compute contrast, don't estimate it.** For each text/background and
  UI/background token pair, run `python3 scripts/contrast.py <fg> <bg>` from this
  skill's directory, or apply the WCAG relative-luminance formula. Do this in
  every supported theme.
- **Never rely on color alone.** Pair it with an icon, text or pattern
  (errors, status chips, chart series).
- If dark mode is in scope (see the brief's Themes line), define light and dark
  as token sets, not ad-hoc overrides, and check both.

### 5. Components and states: consistent and complete

- Same thing, same look, same place. Reuse existing components before
  inventing new ones.
- Every interactive element has all of these states designed: **default,
  hover, focus-visible, active, disabled, loading**. Data views and forms also
  need **empty, error, and success** states.
- Clear affordances:
  - Buttons look pressable, and links look like links.
  - Inputs have visible boundaries and **persistent labels**, not placeholder-only.
  - Error text sits next to its field and is programmatically tied to it.
- Pointer targets ≥ 24×24 px or adequately spaced (WCAG 2.2 AA floor, all
  devices). ≥ 44×44 px wherever touch is in the brief's context.
- Keyboard: every control is reachable in a logical focus order, and the
  focused element is never hidden behind sticky headers or footers.
- Dragging needs a single-pointer alternative, such as buttons or a menu.
- Auth and forms:
  - Allow paste and password managers.
  - Don't ask for the same information twice in one flow.

### 6. Restraint: remove before adding

- Every element must serve the brief's job. If it doesn't, cut it.
- Limit choices per view (Hick's Law). Put advanced options behind progressive
  disclosure rather than showing everything.
- Visual polish (shadows, gradients, motion) comes last and must not reduce
  legibility or contrast. Respect `prefers-reduced-motion`.

## Review checklist

Run this before presenting a design, or when asked to review one. Report each
failure with the element, the rule broken, and the fix.

- [ ] A design brief exists (or an `Assumed:` note for small tweaks), and every default is stated.
- [ ] One clear primary action and focal point, verified as described in Hierarchy.
- [ ] All spacing comes from the scale, and groups are separated by proximity.
- [ ] ≤ 2 typefaces; sizes from the type scale; body ≥ 16 px (14 px only for dense expert tools); readable line length.
- [ ] Text contrast ≥ 4.5:1 and UI/focus contrast ≥ 3:1, computed, in every supported theme.
- [ ] No information is conveyed by color alone.
- [ ] All interactive states are present, including focus-visible; empty, error and loading states are designed.
- [ ] All pointer targets ≥ 24×24 px or adequately spaced; ≥ 44 px where touch is in context.
- [ ] Every control is keyboard-reachable in a logical order, and focus is never hidden by sticky UI.
- [ ] Reflows at 320 px with no horizontal scroll; text survives 200% resize.
- [ ] Auth fields allow paste; dragging has a single-pointer alternative.
- [ ] Consistent with the existing design system named in the brief.

## Additional resources

- `references/visual-design.md`: token examples, type and spacing scales,
  layout patterns, button rules, and common visual mistakes with fixes.
- `scripts/contrast.py`: computes the WCAG contrast ratio for color pairs and
  reports AA/AAA pass or fail.
