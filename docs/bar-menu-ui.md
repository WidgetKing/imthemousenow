# The bar widget UI

What the bar widget is, now that it is built. This was a specification; it is
now a description, kept because the reasoning in it is not recoverable from the
QML.

Code: `shell/Panel.qml`, `shell/Model.js`, `shell/manifest.json`. The widget
validates nothing itself — every read is `imthemousenow-config env`, every
write is `imthemousenow-config set` or `toggle`, so the config program stays
the only thing that knows what a valid value is. `tests/panel-settings.sh`
puts every key the panel writes to the real `set`, so a key renamed in
`config.default.toml` fails a test rather than a click.

---

## 1. What was removed

**The hold's pulsing ring.** Three rings of falling alpha, drawn around the
pointer for as long as a hold held the button. The pixel mark is drawn over the
top of it, so the rings underneath were decoration hidden by the thing that
replaced them. Gone: `action.hold.halo_size`, the ring drawing in
`qml/halo.qml`, and `--color` / `--size` on `bin/imthemousenow-halo`.

One consequence, decided rather than inherited: **the hold's mark is no longer
governed by `pool.enabled`.** That setting used to choose between the mark and
the rings; with the rings gone it would have chosen between the mark and
nothing, and nothing is a keyboard where every key means something new with no
sign that a button is down. So `pool.enabled` now governs only the flourish a
*click* leaves behind. A hold always marks its pointer, and reads its size,
chunkiness and style from `[imthemousenow.pool]` regardless.

**`action.drag.drop_mode`.** Which MODE the second pass of a drag opened in.
Present practice — always the MODE that picked up — is now the only practice.

**Default Action.** The setting stays in `config.toml` and still shows in the
hero line; the panel reports what the chord will do without offering to change
it. (`scroll` was already a valid value, so nothing needed adding there.)

**Click-mark speed.** Not built. How long a mark lasts is derived from the
double-click window, and that coupling is the point — the mark disappears
exactly when the chance to double click does.

**`[imthemousenow.double_click]` moved** below the `ADVANCED` divider in
`config.default.toml`, so the file and the panel agree about where it belongs.

## 2. The bar button

| | |
|---|---|
| Glyph | `󰇀` |
| Left click | opens/closes the panel |
| Right click | runs `imthemousenow` — so the button is also a way to point |
| Shows state | no |

## 3. The tabs

`Behaviour` · `Overlay` · `Feedback` · `Advanced`, each with a membership rule
so a new setting has an obvious home:

| Tab | Rule | Rows |
|---|---|---|
| **Behaviour** | changes what a keypress *does* | 6 |
| **Overlay** | what is drawn over the screen while you are choosing | 6 |
| **Feedback** | what is drawn *because of* what you chose | 3–11 |
| **Advanced** | needs an explanation before you would touch it | 6 |

Overlay and Feedback began as one `Appearance` tab and came out at 17 rows,
nearly three times either neighbour. The line between them is not a count: the
overlay is the surface you read a label off, while the action word, the click
mark and the scroll mark all appear *because of* something you did. It is also
a seam the code already has — `wl-kbptr` draws the first, `imthemousenow-osd`
and `qml/PoolSpot.qml` draw the second — rather than one invented to even out a
tab strip.

Feedback is still the longest, but it is the most collapsible: five rows hide
when the action word is off and three when the click mark is off, so it runs
from 3 rows to 11 where Overlay is a flat 6. No split gets two even halves
without cutting through a group — separating the word from the marks would give
7 and 10, but needs five tabs, and four is what fits at 380px.

Advanced's rule is about whether a setting can carry its own label, not about
where it sits in the config file. Double click is the case that settled it: it
has no wrong answer, so it is a preference, and you would still only change it
once someone explained what pressing the committing key twice is for.

**Advanced is not a form for every tuning constant.** `continuous.*`,
`double_click.guard_ms`, `resize.step`, `intro_chunk` and the rest are
described in the config as "Not preferences. If one of these needs changing,
something is wrong and the fix is probably code." A slider on those invites
exactly the fiddling that warns against, and a wrong value there makes a subtly
broken overlay rather than an ugly one. They stay behind Edit config.
`switch.settle_ms` is the one exception, and it earns it: whether `0` is safe
is an open question, and a slider makes testing it a drag rather than an
edit-and-reload.

## 4. Behaviour

| Row | Control | Config key | Values |
|---|---|---|---|
| Default Mode | chips | `defaults.mode` | hints, grid |
| Default Scope | chips | `defaults.scope` | window, monitor |
| Default Lifetime | chips | `defaults.lifetime` | single, continuous |
| Modifier side | keyboard picker | `keyboard_modifier_side` | left, right |
| Hold speed | slider | `action.hold.step` | 5–120 px, step 5 |
| Drag time | slider | `action.drag.duration_ms` | 100–1000 ms, step 50 |
| Notifications | toggle | `notify` | on/off |

`windows` is a valid `defaults.mode` and is deliberately not offered; it stays
settable by hand.

**Drag time is named for what it is, not for what was asked.** The setting is a
duration — how long the pointer takes to walk from what a drag picked up to
where it drops — so a slider labelled "speed" would get *slower* as it moved
right, directly contradicting Hold speed immediately above it, which gets
faster. Longer is also more reliable: a client reads drag-and-drop out of the
motion events under a held button, and one jump from A to B is a single event
for it to infer everything from. Raising it is the fix when an application
keeps missing a drop. Rename the label if you would still rather have "speed" —
nothing but the label depends on it.

### The modifier-side picker

Two halves of a split keyboard, tilted away from the middle, drawn rather than
named. The setting is spatial — which half flips axes and which half holds
modifiers for the click — and two chips reading "left" and "right" make you
translate that into a picture yourself. The gap down the middle *is* the
setting.

The command half is filled in the accent colour and marked `⇧ ⌥ ⌃`; the other
reads `hold`. So the picture says what each side *does*, not just which side is
which.

One inversion worth knowing when reading the code: `keyboard_modifier_side`
names where the *modifiers* are held, but what a person is choosing is which
hand gives orders. Clicking a half means "this half commands", so the setting
is written as the opposite value.

## 5. Overlay

| Row | Control | Config key | Values |
|---|---|---|---|
| Opacity | slider | `opacity.default` | 0.30–1.00, as % |
| Peek | slider | `peek_alpha` | 0.05–1.00; 1.00 = "off" |
| Rad Animations | dropdown | `intro` | bytes, interlace, scanline, dropout, roll, beam, shuffle, random, none |
| Animation speed | slider | `intro_ms` | 0–600 ms, step 25 |
| Theme colours | toggle | `theme_colors` | on/off |
| Theme font | toggle | `theme_font` | on/off |

Peek sits here rather than in Behaviour because it is the same control on the
same object as Opacity, and that is where a hand looks for it.

### Rad Animations

A dropdown rather than chips, because the list was expected to grow and has:
nine values as of the ones added in the fork's "Nine more ways for the overlay
to arrive". Chips are a
row that gets longer until it wraps, a dropdown is a row that stays one line at
any length. The list opens *inline*, below the row, rather than floating over
it — the panel is a Flickable, and a floating list has to be positioned against
a surface that scrolls under it.

The config key accepts a **list**: `intro = "bytes,scanline"` means "pick at
random between these two". A dropdown of single values cannot express that, so
a value it does not recognise renders as itself, dimmed, rather than snapping
to the first option. The panel must never quietly rewrite a setting it merely
failed to understand.

The config key is still `intro`. `Rad Animations` is the label.

## 6. Feedback

| Row | Control | Config key | Values |
|---|---|---|---|
| **Action word** | chips | `osd.enabled` + `osd.ascii` | Off, Font, Block letters |
| — Position | chips | `osd.position` | top, center, bottom |
| — Size | slider | `osd.size` | 40–200 px |
| — Time on screen | slider | `osd.ms` | 250–3000 ms |
| — Fade | slider | `osd.fade_ms` | 0–1000 ms |
| — Announce on start | toggle | `osd.on_start` | on/off |
| **Click mark** | toggle | `pool.enabled` | on/off |
| — Size | slider | `pool.radius` | 16–120 px |
| — Chunkiness | slider | `pool.cell` | 2–16 px |
| — Style | dropdown | `pool.style` | pool, patchy, lines, cross, random |
| Scroll mark size | slider | `action.scroll.mark_size` | 16–96 px |

Rows marked `—` are indented and hidden when their group's first row is off.

### Action word: one three-way row, two config keys

`Off` · `Font` · `Block letters`. The old shape was a toggle plus a separate
block-letters toggle, which let you turn block letters on for a word that was
off — a setting with nothing to mean. Three options is what a person actually
chooses between.

It writes two keys: `Off` → `osd.enabled=false`; `Font` → `enabled=true,
ascii=false`; `Block letters` → `enabled=true, ascii=true`. Two writes from one
press is fine — the panel queues writes one at a time, so the second reads the
config the first wrote.

## 7. Advanced

| Row | Control | Config key | Values |
|---|---|---|---|
| Double click | toggle | `double_click.ms` | on (`system`) / off (`0`) |
| Popup-safe overlay | toggle | `popups.keep_open` | on/off — hidden on stock `wl-kbptr` |
| Key sheet size | slider | `help.size` | 10–28 px |
| Switch settle | slider | `switch.settle_ms` | 0–200 ms, step 10 |
| Edit config… | button | — | opens `config.toml` in the editor |
| Check | button | — | runs `imthemousenow-config check` |

**Double click** is not a boolean in the config — it is `system`, a number of
ms, or `0`. On writes `system`, the desktop's own double-click time, which is
the number the applications being clicked measure against. Off writes `0`. A
custom number set by hand reads as "on"; that is the cost of the simpler
control.

## 8. Keyboard model

| Key | Does |
|---|---|
| `j` / `k`, arrows | previous/next row within the tab |
| `h` / `l` | chips and dropdowns: move the highlight **without applying**; slider: change by one step, **applied immediately**; toggle: nothing |
| `Enter` | chips: apply; dropdown: open, then apply; toggle: flip; button: press |
| `[` / `]` | previous/next **tab** |
| `e` / `c` | jump to Advanced and activate Edit config… / Check |
| `Tab` | switch to the next **bar panel** (unchanged) |
| `Escape` | shut an open dropdown, or close the panel |

`Tab` could not switch tabs — it is already `switchPanel()`, moving between
this widget and the next in the bar. `[` and `]` are free, read as sideways,
and do not collide with `h`/`l`, which work inside a row.

Switching tabs resets the cursor to the first row: a position in the old tab
does not exist in the new one.

**The chips/sliders asymmetry is unchanged** — `h`/`l` applies on a slider and
not on chips — because it was an open question and nothing said to settle it.
Dropdowns follow the chips, so the two kinds of list behave alike.

## 9. Verified on the compositor

All of it, by hand, on the running shell: the four tabs and their widths, the
modifier-side picker, the inline dropdowns, and the hold's mark with
`pool.enabled` off — the one case the removed ring used to cover, and the only
place the removal changed behaviour rather than just deleting it. The scroll's
Space and Return exits were checked after a `hyprctl reload`.

What the automated tests do and do not cover, for anyone changing this later:
`tests/panel-settings.sh` pins every config key the panel writes to the real
`set`, and checks that the rows the cursor walks are the rows that get drawn.
It cannot see layout. `qmllint` parses the files but its imports of `qs.Ui` and
`qs.Commons` do not resolve outside Omarchy's shell, so it cannot confirm a
component exists with the properties used. Anything visual still needs a
`quickshell` reload and an eye.

## 10. Still open

- Should chips apply as you walk them, matching sliders?
- Should the bar button show current state — the ACTION alone, or the whole
  chord?
