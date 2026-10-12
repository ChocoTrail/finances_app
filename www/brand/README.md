# Finance app visual assets

These files keep the deployed interface self-contained and avoid runtime
dependencies on an external font service.

## Fonts

- `Recursive-Variable.ttf`: interface text, headings, labels, and controls.
- `AzeretMono-Variable.ttf`: currency, measured values, tables, charts, and
  compact metadata.
- `OFL-*.txt`: the corresponding Open Font License files.

When the client stylesheet is created, define local `@font-face` rules for
these files and use `font-display: swap`.
