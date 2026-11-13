# Third-party notices

EGA EDIT is MIT-licensed (see [LICENSE](LICENSE)), but it bundles material
that keeps its own licence:

## Turbo Vision

`vendor/tvision/` is the source of [magiblot/tvision](https://github.com/magiblot/tvision),
Borland's Turbo Vision 2.0 made public and modernised. It keeps Borland's
public licence; see [vendor/tvision/COPYRIGHT](vendor/tvision/COPYRIGHT).

## PxPlus IBM VGA8 and the glyph atlas

`tools/fonts/PxPlus_IBM_VGA8.ttf` is *PxPlus IBM VGA8* from VileR's
[Ultimate Oldschool PC Font Pack](https://int10h.org/oldschool-pc-fonts/),
licensed under
[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).

The native macOS edition does not load the font at runtime. Instead it ships a
pre-rendered CP437 glyph atlas derived from it:

- `native/Resources/glyphs.bin`
- `native/Resources/glyphs.json`

That atlas is a derivative of the font and is distributed under the same
CC BY-SA 4.0 licence. `native/tools/make_glyphs.py` regenerates it.

The app icon (`native/Resources/AppIcon.icns`) and the documentation screenshots
in `docs/` were rendered with the same font and carry the same attribution.
