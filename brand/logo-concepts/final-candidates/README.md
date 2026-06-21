# TokenStep Final Logo Candidates

These final candidates now use the upper-right GPT Image 2 Flat direction as the selected production path, recolored with a GitHub contribution-wall green progression.

## Recommendation

Use `svg/07-step-arc-app-icon.svg` as the main app icon.

Keep the macOS menu bar icon as the existing dynamic progress ring rendered by `StatusBarIconRenderer`. Do not use the Step Arc logo as the menu bar icon.

Use `svg/10-tokenstep-step-arc-lockup.svg` for README and website display.

## Why This Is Better Than The Previous Version

- Matches the user-selected upper-right concept more directly: a daily progress arc over increasing token usage.
- Keeps the blocks rounded and token-like, so the mark reads as token progress rather than a generic analytics chart.
- Removes soft raster artifacts from the GPT Image 2 concepts.
- Uses a tighter small-size silhouette for 16, 18, 22, 32, 64, 128, 512, and 1024 px exports.
- Splits the system into production roles: Step Arc for app/brand surfaces, progress ring for the live menu bar, and horizontal lockup for README / website display.

## Candidate Files

- `svg/07-step-arc-app-icon.svg` - recommended main app icon
- `svg/08-step-arc-menu-color.svg` - transparent color icon for docs only, not the macOS menu bar
- `svg/09-step-arc-menu-template.svg` - archived template experiment; do not use for the macOS menu bar
- `svg/10-tokenstep-step-arc-lockup.svg` - horizontal lockup for README / website
- `svg/01-daily-orbit-app-icon.svg` - previous green orbit candidate
- `svg/02-token-step-orbit-app-icon.svg` - stronger step-progress alternate
- `svg/03-compact-orbit-app-icon.svg` - simplified app icon fallback
- `svg/04-menu-bar-color.svg` - small transparent color icon
- `svg/05-menu-bar-template.svg` - monochrome `currentColor` template icon
- `svg/06-tokenstep-lockup.svg` - horizontal lockup for README / website

## PNG Exports

Icon PNG exports are in `png/` at:

- `16`
- `18`
- `22`
- `32`
- `64`
- `128`
- `512`
- `1024`

Lockup PNG exports are in `png/` at:

- `320`
- `600`
- `1200`

## Preview And Comparison

- `index.html` - local preview page for all candidates
- `contact-sheet.png` - final candidate overview
- `small-size-comparison.png` - native small-size comparison, enlarged for review

## Production Constraints

All SVG files use solid flat colors only. They contain no `linearGradient` or `radialGradient` definitions.
