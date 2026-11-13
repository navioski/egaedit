# Turbo Vision Style TUI Design Spec

> In one line: **CUA layout + Turbo Vision skeleton + EGA 16 colours + character art.**
> Everything on screen is a glyph and a background colour inside a character cell. Nothing is drawn freely in pixels.

---

## 1. Name and lineage

| Layer | Name | Notes |
|---|---|---|
| Hardware | **text mode / character mode** | 80×25 cells, 9×16 glyphs, 16 colours |
| Design language | **CUA** (Common User Access, IBM 1987) | menu bar, windows, dialogs, status line |
| Implementation style | **Turbo Vision** (Borland, 1990) | CUA turned into a DOS window library — this is where the look comes from |
| Common name | **DOS TUI / Turbo Vision style / ANSI art** | the first for interaction, the second for 16-colour character art |

Modern recreations usually add a layer of **CRT simulation** (scanlines, shadow mask, curvature). That is the monitor flavour, not the UI.

---

## 2. The hardware prototype: why it looks like this

Understanding the constraints matters more than memorising the style:

1. **One character cell = one pixel unit.** A "1px border" is one character wide and cannot be made thinner.
2. **Non-square pixels.** 320×200 stretched to 4:3 gives pixels that are 1:1.2 (tall). Blocky letters therefore look thin and tall.
3. **16 colours, no anti-aliasing.** Shadows and gradients can only be suggested with **characters** (`░▒▓`) and dithering.
4. **No compositing.** A window shadow is a block of black characters, not translucency.

> In a modern terminal: horizontal lines can be split in half (`▀`), vertical lines cannot — which happens to match the original limitation.

---

## 3. Colour system

### 3.1 EGA/VGA 16-colour palette (standard values)

| # | Name | Hex | # | Name | Hex |
|---|---|---|---|---|---|
| 0 | black | `#000000` | 8 | dark gray | `#555555` |
| 1 | blue | `#0000AA` | 9 | light blue | `#5555FF` |
| 2 | green | `#00AA00` | 10 | light green | `#55FF55` |
| 3 | cyan | `#00AAAA` | 11 | light cyan | `#55FFFF` |
| 4 | red | `#AA0000` | 12 | light red | `#FF5555` |
| 5 | magenta | `#AA00AA` | 13 | light magenta | `#FF55FF` |
| 6 | brown | `#AA5500` | 14 | yellow | `#FFFF55` |
| 7 | light gray | `#AAAAAA` | 15 | white | `#FFFFFF` |

### 3.2 Classic Turbo Vision scheme (approximate)

| Role | Foreground | Background |
|---|---|---|
| Desktop | — | blue `#0000AA` |
| Window frame / title | light gray `#AAAAAA` | blue |
| Window content | black | light gray `#AAAAAA` (or black on cyan) |
| Dialog | black | light gray |
| Dialog title | white | blue |
| Menu bar | black | light gray |
| Selected menu item | white | blue (or black on bright gray) |
| List box selection | black | cyan `#00AAAA` (reverse) |
| Input field | black | cyan (or white) |
| Status line | black | light gray |
| Hotkey letters | **highlighted** (`~X~`) | the surrounding control |

### 3.3 Usage rules

- **Dark base, bright for action**: a large background uses one dark colour only (blue / black / dark gray).
- **No more than four hues on one screen**: cyan, magenta, green and yellow are "functional" colours; do not scatter them.
- **Bright colours only for focus and status**: the current window, the selection, a warning.
- **Greyscale via dithering**: 16 colours have no mid-grey; `░` (25%), `▒` (50%) and `▓` (75%) stand in for it.

---

## 4. Layout

### 4.1 Screen regions (80×25)

```
┌──────────────────────────────────────────────────────────────┐
│ ≡  Viewer   The wall   Versions   Options   Theme      About │  ← menu bar, 1 row
├──────────────────────────────────────────────────────────────┤
│                                                              │
│   Desktop: windows float here, stacked and draggable          │
│                                                              │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│ Status line: shortcuts / current object / line and column    │  1 row, black on light gray
└──────────────────────────────────────────────────────────────┘
```

- The menu bar is **1 row**, the status line **1 row**, and everything between is desktop.
- The desktop may use a `░` dither or a solid colour. Do not draw patterns on it.

### 4.2 Window anatomy

```
╔═ Scenes ══════════════════════════╗
║ Lucasfilm Games                   ║░
║ Mêlée Island                      ║░
║ The lookout                       ║░
║ The docks                         ║░
╚═══════════════════════════════════╝░
 ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
```

| Part | Spec |
|---|---|
| Border | **double line** `╔═╗║╚╝`, 1 cell thick |
| Title | **embedded in the top border**, one space on each side: `╔═ Title ═╗`, centred |
| Close box | top-left `[■]`, 2 cells |
| Zoom box | top-right `[↑]` or `[■]` |
| Shadow | offset one cell right and down, `░` or `█` (black), **bottom-right only** |
| Content | inside the border, at least 1 cell of padding |
| Focus | the current window's title is reversed (bright on blue); the others stay grey |

### 4.3 Dialog anatomy

```
    ╔═ Open ══════════════════════════╗
    ║ File name: ╔══════════════════╗  ║
    ║            ║ notes.txt        ║  ║
    ║            ╚══════════════════╝  ║
    ║                                  ║
    ║        ┌────────┐  ┌────────┐    ║
    ║        │   OK   │  │ Cancel │    ║
    ║        └────────┘  └────────┘    ║
    ╚══════════════════════════════════╝
```

- Dialogs are **centred**, with at least 2 cells of margin.
- The default button is wrapped in **`◄ ►`** (`◄ OK ►`) or drawn with a double-line frame; Enter triggers it.
- Input fields use a **single-line frame plus a white/cyan background**, one step brighter than the surroundings.

---

## 5. Components

| Component | Drawing | Notes |
|---|---|---|
| Window frame | `╔═╗║╚╝` | title embedded in the top edge |
| Dialog | `╔═╗║╚╝` + grey background | same structure as a window, usually no shadow or a lighter one |
| Button | `┌────┐` + centred text | 1 cell margin; pressed state is `└────┘` reversed |
| Default button | double frame `╔════╗` | or `◄ OK ►` |
| Input field | single-line frame + bright background | cursor is a bright block |
| Checkbox | `[X]` / `[ ]` | the brackets are the border |
| Radio | `(*)` / `( )` | parentheses suggest the circle |
| Dropdown | `▼` on the right | expands to an overlapping list box |
| List box | selection bar on the left + scrollbar | the selected row is fully reversed |
| Scrollbar | track `░` + thumb `█` | arrows `▲▼` at the ends |
| Status line | full row + `│` separators | write out the shortcuts, not just icons |
| Progress bar | `█` fill + `░` remainder | add a percentage |
| Separator | `─` or `═` | for grouping; do not overuse |

### Menus

```
 File   Edit   Search   Options
 ┌──────────────────────────┐
 │ New        Ctrl-N        │
 │ Open...    Ctrl-O        │
 ├──────────────────────────┤
 │ Save       Ctrl-S        │
 │ Save as...               │
 └──────────────────────────┘
```

- Menu items are **left-aligned**; shortcuts are **right-aligned**.
- Groups are separated with a `├────┤` line, not a blank row.
- Disabled items are **dimmed** (`#555555`), not removed.

---

## 6. Character set (UI drawing uses only these)

| Purpose | Characters |
|---|---|
| Single-line frame | `┌ ┐ └ ┘ ─ │ ├ ┤ ┬ ┴ ┼` |
| Double-line frame | `╔ ╗ ╚ ╝ ═ ║ ╠ ╣ ╦ ╩ ╬` |
| Blocks | `█ ▓ ▒ ░ ▄ ▀ ▌ ▐` |
| Shadow | `░` (light) / `█` (heavy) |
| Arrows | `▲ ▼ ◄ ►` |
| Checks | `[X]` `(*)` `•` |
| Emphasis | reverse video (bright background, dark text); never italics or bold |

> Do not use emoji or modern icon fonts — one of them and the era is gone.

---

## 7. Typography

- **Font**: monospaced bitmap. DOS used 9×16 (IBM VGA; for modern recreations, VileR's PxPlus IBM VGA8/9, CC BY-SA).
- **Size**: one size only. Hierarchy comes from **reverse video, borders and indentation**, not from font size.
- **Case**: menus and buttons use Title Case; the status line may be all caps; titles are centred.
- **Spacing**: 1 cell between controls, 2 cells between groups; at least 1 cell of padding inside content areas.
- **Alignment**: mostly left, numbers right, titles centred.

---

## 8. Interaction

- **Keyboard first**: `F10` for the menu, `Alt+letter` to jump, `Tab` to cycle focus, `Esc` to cancel, `Enter` for the default button.
- **Visible hotkeys**: menu and button hotkeys are marked with a **highlighted letter** (`~F~ile`).
- **Mouse optional**: clicking is nice, but everything must be reachable from the keyboard.
- **Explicit focus**: exactly one control is reversed at a time; unfocused controls return to grey.
- **No animation**: menus and dialogs appear instantly; the only motion is the cursor blinking (about 500 ms).

---

## 9. Implementing in a modern terminal

| Problem | Approach |
|---|---|
| Canvas | keep a 2D array `cell[y][x] = (char, fg, bg)` |
| Output | absolute positioning per row (`CSI r;1H`); do not rely on `\n` (raw mode does not return the carriage) |
| Redraw | full-frame redraw is fine; add dirty rectangles only if you need more speed |
| 1px horizontal line | build it from `▀` upper/lower half blocks: 1 cell = 2 vertical pixels |
| 1px vertical line | impossible; use `▌`/`▐` (half-width) or a full `│` cell |
| 16-colour fallback | map true colour to the nearest EGA colour; design for 16 colours first |
| Wide characters | CJK takes two cells: lay out by display width and skip "continuation" cells when writing |
| Shadow | offset one cell right and down, fill with black-background characters |
| Cursor | reversed block + timed blink; repaint only that cell |

---

## 10. Checklist

**Do**

- [ ] Every border is 1 cell thick
- [ ] Window titles sit inside the border, centred
- [ ] Shadows are bottom-right only, and exactly 1 cell
- [ ] No more than 4 hues per screen; one dark background
- [ ] Focus is reversed and only one control has it
- [ ] Menu items have right-aligned shortcuts
- [ ] The status line lists the full shortcuts
- [ ] Everything is readable in 16 colours

**Don't**

- [ ] Rounded corners, gradients, translucency
- [ ] Emoji, icon fonts, anti-aliased bitmap fonts
- [ ] Critical actions that only appear on mouse hover
- [ ] Icon-only buttons without a text label
- [ ] Animation / transitions / blurred shadows
- [ ] Decorative colours beyond 16

---

## 11. References

- **Turbo Vision** (Borland, 1990; modern open-source remake: magiblot/tvision)
- **CUA** — IBM Common User Access specification (1987/1989)
- **VileR, PxPlus IBM VGA 8/9** — a recreated 9×16 bitmap font (CC BY-SA)
- **DOSBox Staging** CRT shaders (`crt-hyllian`, `crt-auto-machine`): the "monitor glass" for this UI
- **monkeyisland.pages.dev** — a web implementation that takes this spec to the limit: IBM VGA font, EGA palette, double-line windows, CRT lab
