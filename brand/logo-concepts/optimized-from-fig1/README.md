# TokenStep Logo Optimization From Figure 1

Source direction: `../gpt-image-2-flat/01-flat-progress-orbit-gpt-image-2.png`

Optimization goal: keep the recognisable green daily progress orbit and token blocks, but make the mark cleaner, flatter, and easier to read at small app/menu-bar sizes.

Main problems in figure 1:

- The center grid has too many similar dark blocks, so it becomes muddy at small sizes.
- The endpoint dot floats slightly away from the ring and feels less intentional.
- The ring is strong, but the gap position and center mass can be better balanced.
- The app tile still has raster softness from image generation; production assets should be vector-flat.

Recommended direction:

- Start with `01-balanced-orbit.svg`.
- If the icon needs to survive tiny menu-bar sizes, use `03-menu-size.svg`.
- If the logo should feel more unique and less like a generic progress ring, test `04-single-token-core.svg`.

All SVGs in this folder use solid flat colors only. No gradients, shadows, glows, bevels, or 3D effects.
