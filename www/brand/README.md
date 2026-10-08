# Choco Trail web assets

These files are approved deployment copies from the Choco Trail personal brand
package. Keeping them in the application makes the deployed interface
self-contained and avoids runtime dependencies on a sibling repository or an
external font service.

## Fonts

- `Recursive-Variable.ttf`: interface text, headings, labels, and controls.
- `AzeretMono-Variable.ttf`: currency, measured values, tables, charts, and
  compact metadata.
- `Mina-Bold.ttf`: Choco Trail wordmark use only.
- `OFL-*.txt`: the corresponding Open Font License files.

When the client stylesheet is created, define local `@font-face` rules for
these files and use `font-display: swap`.

## Logos

The `logo/svg/` directory contains approved outlined lockups, wordmarks, and
marks in Ink, Paper, and Current. Do not edit their internal geometry or use
the SVGs as general-purpose interface icons.

The `logo/favicon/` directory contains the approved favicon SVG and raster
fallbacks.

The finance application is an endorsed project. Keep its own name primary and
use Choco Trail branding quietly in a footer, about surface, or similar
secondary location.
