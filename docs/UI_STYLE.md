# UI style

Every HUD element and menu in the game shares one look, defined in
`scripts/ui/ui_style.gd` (`UiStyle`). The `UiTheme` autoload merges
`UiStyle.theme()` into Godot's default theme before anything is built, so a
plain `Button.new()` or `PanelContainer.new()` already comes out styled. You
rarely need colour or font overrides.

## The idea

- **Driving:** the 2013 500's round cream dial with an amber dot-matrix
  screen (`DashCluster`). It switches to its night lighting with the
  headlights.
- **Menus:** a printed cream card with an ink rule and a hard shadow, tomato
  red for actions and selection, Indian Ocean teal for progress.
- **Field journal:** a cloth-covered notebook with ruled pages; hints are
  pencilled and M.'s 1979 pages are in blue fountain pen (`HandLabel`).
- **Over the world:** small cream chips (toasts, prompts, the status strip),
  dimmed a little at night.

## Palette

| Name | Use |
| --- | --- |
| `PAPER`, `PAPER_2`, `PAPER_3` | card, buttons and wells, rules |
| `INK`, `INK_2`, `INK_3` | text, secondary text, hints and disabled |
| `RED`, `RED_DARK` | primary actions, selection, section headings |
| `TEAL`, `TEAL_LIGHT` | progress, the ocean |
| `SUN`, `SUN_LIGHT` | highlights, hover |
| `NIGHT`, `NIGHT_2` | dark cards, the phone's bezel, the dial at night |
| `LCD`, `LCD_BG`, `LCD_DIM` | amber readouts (dial screen, radio, film counter) |
| `CREAM_TEXT` | text straight over the world or on red |
| `BLUE_INK` | M.'s pages |

## Fonts (`ui/fonts`, SIL OFL)

- **Jost** (`BODY_FONT`, `BOLD_FONT`): everything by default.
- **DM Serif Display** (`TITLE_FONT`): titles, via the `TitleLabel` variation.
- **VT323** (`LCD_FONT`): amber readouts, via `LcdLabel`.
- **Caveat** (`HAND_FONT`): handwriting, via `HandLabel`.

## Theme variations

Set `theme_type_variation` to one of these:

- Labels: `TitleLabel`, `SectionLabel` (small red caps; set `uppercase`),
  `NoteLabel`, `HandLabel`, `LcdLabel`, `WorldLabel` (cream with an outline,
  for text straight over the world).
- Panels: `PanelContainer` is the cream card by default; also `DarkPanel`,
  `WellPanel`, `ChipPanel`, `LcdPanel`, `BarePanel`.
- Buttons: `Button` is the cream button; `PrimaryButton` is the red one (one per
  screen), `ListButton` is a flat row that highlights when chosen (use
  `toggle_mode` and a `ButtonGroup`).

## Building blocks

- `UiStyle.centred_card(parent, min_size)` returns `[panel, vbox]`.
- `UiStyle.header(parent, title, icon, subtitle, close_text)` returns
  `[title, subtitle, close_button, row]`.
- `UiStyle.section(parent, "Heading")`: a red caps heading with a rule.
- `UiStyle.label(parent, text, variation, size, colour)`.
- `UiStyle.backdrop()`: the warm dim behind a menu.
- `UiStyle.icon(name, px, ink, size, accent)`: line icons drawn from inline SVG
  (see `ICONS`; no image files). `UiStyle.icon_rect(...)` wraps one in a
  `TextureRect`.
- `UiStyle.keycap("F")`: a key or gamepad button.
- `PromptChip`: an on-screen prompt. Set `.text` the way you'd set a Label's
  ("F  Get in", "Hold F  Get out", "F / A: use the workshop", a title line
  above with `\n`). It shows the gamepad button once the player uses a pad,
  and hides itself while the game is paused. Place it with `place_bottom(px)`.
- `TitleArt`: the title screen's look (wordmark, tagline, menu buttons).
- `SpeciesIcon.bird(species, px, silhouette)` / `SpeciesIcon.fish(...)`: a
  field-guide plate drawn from the species' `model` and `colours` in
  `data/field`, so new species get one automatically. Pass `silhouette` for a
  pale pencil outline (not yet seen). Odd ones can be tuned in `BIRD_TWEAKS`.
  `tools/species_sheet.gd` renders them all on one sheet for checking.
- `UiStyle.animate(panel)`: the quick pop-in and the soft open/close sounds.
  `centred_card()` already does it. Buttons tick when moved between with the
  keys or a pad and click when pressed (the `UiTheme` autoload), using the
  audio thread's `audio/ui` sounds.

## Scaling

The UI is laid out for 1280x720 and scaled to the window (`canvas_items`
stretch). The lo-fi framebuffer is still sized from the window's real pixels
(`scripts/main.gd`), so the 3D look doesn't change with the window. Players can
pick Small, Normal or Large for menus and HUD, and full screen (F11), in the
pause menu.

## Screenshots

`tools/ui_screens.gd` opens every screen in turn and saves a PNG of each:

    xvfb-run godot --path . --fixed-fps 60 --resolution 1280x720 \
      --script res://tools/ui_screens.gd -- --no-save shots=/tmp/ui
