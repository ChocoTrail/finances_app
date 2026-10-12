# Choco Trail brand essentials

> This is the finance application's checked-in reference for the color,
> typography, spacing, and accessibility principles adapted from the Choco
> Trail design system. The app does not display the Choco Trail name or logo.

Choco Trail is a personal identity for exploratory projects, analytical work, and small tools with personal implications. It signals that the work is considered and cared for without presenting it as institutional, corporate, or grander than it is.

The system is personal infrastructure: a dependable set of defaults that removes repeated design decisions while leaving each project free to use, adapt, or ignore parts of the system.

## Character

The identity rests on three ideas:

1. **Quiet rigor** is the foundation. Work should feel clear, trustworthy, structured, and substantively useful.
2. **Restrained idiosyncrasy** is the signature. Typography, small details, and unusual but controlled choices keep the work from feeling generic.
3. **Plainspoken experimentation** is the voice. Exploratory work can be candid about uncertainty without becoming vague, hyped, or careless.

Choco Trail should feel humble, distinctive, warm, technically capable, and intentionally made.

Avoid bombast, generic technology aesthetics, gradients used as personality, exaggerated animation, corporate polish without substance, and anything that resembles unedited AI output.

## Origin and visual references

The name comes from Choco Trail, a childhood street near Parker, Arizona and the Colorado River. It became a recurring online handle and accumulated personal meaning over time.

The identity's central visual thread is a river or current: movement that is calm, continuous, and directional. A comet is the secondary reference, drawn indirectly from the Korean name "Comet Miller." It appears in the C1 Whisper mark and may name analytical work, but it is not a dominant space motif.

The palette is also informed by family, place, coastal contrast, desert heat, turquoise, and Native jewelry. Choco Trail does not reproduce or imitate Tulalip, Coast Salish, Navajo, or other culturally specific forms or motifs.

## Typography

Both typefaces are open-source Google Fonts.

| Role | Typeface | Working specification |
|---|---|---|
| Interface and body | [Recursive](https://fonts.google.com/specimen/Recursive) | Sans Linear; `CASL 0`, `MONO 0`, `slnt 0`, `CRSV 0.5`; weights 400 and 500 |
| Numbers, tables, charts, and code | [Azeret Mono](https://fonts.google.com/specimen/Azeret+Mono) | Weights 400 and 500; use tabular alignment where appropriate |

### Hierarchy

- Use a balanced working hierarchy: clear differences without oversized display typography.
- Use Recursive 500 for headings and important labels.
- Use Recursive 400 for body text, supporting copy, and controls.
- Use Azeret Mono for measured values, code, table numbers, axis values, and compact technical metadata.
- Use uppercase sparingly, mainly for short metadata or eyebrow labels.
- Favor generous line spacing and relatively short readable line lengths.

## Color

### Foundation

| Token | Hex | Use |
|---|---|---|
| River Stone Paper | `#F4F3EF` | Default page background |
| Ink | `#22292B` | Primary text and high-emphasis structure |
| Surface | `#E5E9E6` | Quiet panels and secondary fields |
| Border | `#C1C9C5` | Rules, dividers, and inactive boundaries |
| Muted | `#5F6969` | Secondary text and nonessential metadata |

### Brand accents

| Token | Hex | Use |
|---|---|---|
| Current Turquoise | `#2F6F73` | Primary accent, links, focus, selected states, information, and primary data |
| Comet Dust | `#8B5E62` | Restrained expressive accent and meaningful comparison data |
| Cinder Red | `#A24E3F` | Error, danger, or explicitly negative data only |

Current should remain recognizable but restrained. Comet Dust is secondary and should never compete with Current. Cinder Red is semantic, not decorative.

### Operational semantic colors

| State | Strong | Soft background |
|---|---|---|
| Information | `#2F6F73` | `#DCE8E7` |
| Success | `#42634A` | `#E1E8DE` |
| Warning | `#7A5B22` | `#EEE4CF` |
| Error / danger | `#A24E3F` | `#F0DCD8` |

Use Ink for text on all soft semantic backgrounds. Use the strong color for an icon, border, focus ring, or solid treatment. On a solid semantic background, use Paper as the foreground.

Do not use semantic colors merely to create variety. Success means successful completion; warning means the user should take notice; error means failure or danger. A rising value is not automatically success, and an outlier is not automatically an error.

### Interface states

- Keyboard focus: Current Turquoise with a separating Paper gap.
- Selected: Current Soft with a Current outline or other non-color cue.
- Disabled: Surface, Border, and Muted; do not rely on opacity alone.
- Hover and pressed: derived changes to Current or the relevant neutral, not new hues.
- Body links: Current Turquoise plus an underline.

## Shape and spacing

### Shape: measured softening

- Surfaces: 3 pixel corner radius.
- Controls: 4 pixel corner radius.
- Chart marks, rules, and structural lines: square or straight.
- Pills: only for genuinely pill-shaped concepts such as tags, statuses, or filters.
- Shadows: none in ordinary layouts; reserve subtle shadows for overlays that must separate from content.

### Spacing: compact rhythm

Use a compact scale based on these working intervals:

- 4: optical adjustment or extremely tight relationships.
- 8: tightly related items.
- 12: default internal spacing.
- 16: component-level separation.
- 24: major section separation.
- 32 and above: exceptional or page-level separation.

Generous space should come from structure and restraint, not uniformly oversized padding.

## Data visualization

The data language is **Quiet Analytical**.

- Use sparse horizontal grid lines and remove unnecessary vertical grids.
- Prefer straight observed connections and visible measured points.
- Do not smooth lines unless the graphic explicitly shows a model or estimate.
- Avoid gradients, decorative area fills, three-dimensional effects, and chart chrome.
- Label important values and series directly when space allows.
- Use Azeret Mono for numeric labels, table values, and compact annotations.
- Use horizontal table rules; avoid boxed cells and dense vertical borders.
- Right-align numeric columns and preserve consistent precision.
- Use Current for the primary series and Comet Dust for a meaningful comparison.
- Use Cinder Red only for genuinely negative or error states.
- Add hues only when more series must be distinguished, and pair color with labels, shapes, or line styles.

## Voice and writing

Write like a thoughtful person showing someone work they care about, not like a company announcing a breakthrough.

The voice is:

- **Plainspoken:** say what something does without inflated language.
- **Specific:** favor concrete details over broad promises.
- **Calm:** communicate confidence without urgency or bombast.
- **Candid:** acknowledge limits, uncertainty, and experimental status.
- **Thoughtful:** give enough context to make decisions understandable.
- **Lightly personal:** warmth and occasional dry wit are welcome when natural.
- **Concise, not sparse:** remove filler without removing useful explanation.
- **Direct:** address the reader and describe what they can do.

Prefer "Use this to compare results and accentuate differences" over "Our advanced platform seamlessly transforms..."

For analytical writing, distinguish clearly between what the data shows, what is inferred from it, and what remains uncertain.

## Iconography and imagery

Neither icons nor imagery are fixed identity elements.

- Use one internally consistent icon family within a project.
- Prefer simple outline icons with restrained rounding and moderate stroke weight.
- Keep icons functional rather than decorative.
- Default icons to Ink, use Current for interaction, and reserve semantic hues for actual status meaning.
- Choose photography, illustration, and artwork per project.
- Avoid generic corporate stock imagery and decorative AI aesthetics.
- Do not imitate or loosely borrow Indigenous forms, patterns, or visual language.

## Accessibility requirements

- Meet WCAG AA contrast: 4.5:1 for ordinary text and 3:1 for large text and meaningful interface graphics.
- Never communicate status through color alone; pair it with text, an icon, shape, or line style.
- Keep keyboard focus visible.
- Do not use Muted for essential labels, instructions, errors, or values.
- Underline body links.
- Distinguish chart series through direct labels, shapes, or line styles in addition to color.
- Prefer interactive targets around 44 by 44 CSS pixels and avoid targets smaller than 24 by 24 pixels except for inline text links and other justified exceptions.
- Support text enlargement and narrow layouts without clipping or page-level horizontal scrolling.
- Avoid unnecessary motion and honor reduced-motion preferences.

References: [WCAG 2.2](https://www.w3.org/TR/WCAG22/), [Understanding non-text contrast](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast), and [Understanding use of color](https://www.w3.org/WAI/WCAG22/Understanding/use-of-color).

## Deliberately open or deferred

The system does not currently define:

- A dark theme.
- A decorative river/current motif.
- A custom icon family.
- A mandatory illustration or photography style.
- A universal categorical chart palette.
- Motion rules beyond restraint and reduced-motion support.
- Social media templates or fixed project layouts.

These are not missing pieces. Add them only after recurring project needs make them useful.

## Asset index

- Web font files and licenses: `www/brand/fonts/`
- The broader source design system remains in the separate `personal_brand`
  project.
