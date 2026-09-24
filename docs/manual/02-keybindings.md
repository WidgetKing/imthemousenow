# Keybindings

`SUPER + ;` is whatever `[imthemousenow.defaults]` says — out of the box hints,
in the window you are already looking at, one left click. Each modifier asks for
the *other* value on exactly one axis, and they compose — so you memorise one
binding plus what three modifiers mean, not eight bindings. ACTION is not among
them, because it is chosen inside the overlay instead.

| Modifier | Flips |
| --- | --- |
| `SHIFT` | SCOPE `window` ↔ `monitor` |
| `ALT` | MODE `hints` ↔ `grid` |
| `CTRL` | LIFETIME `single` ↔ `continuous` |

The flip is resolved when you press the key, not when Hyprland loads, so the
defaults you set in the Pointer widget apply to the next keypress. Change them
to grid-on-monitor and `SUPER + ;` is that, while `SUPER + ALT + ;` is still
"the other mode".

Switch ACTION inside the overlay and its name flashes up in large letters —
solid for a quarter second, then a quarter second of fade. It is the one thing
the overlay cannot show you: `;` changes what a landing does, and a colour tint
is otherwise the only hint that anything changed. Switching back to `left` is
announced too, because by then it is a choice rather than the default.

`SUPER + ;` says nothing, because a left click is what a pointer does when you
have not told it otherwise. `osd.on_start = true` names that one as well, which
is the setting to turn on while the four actions are still new; `osd.enabled =
false` turns the whole thing off.

The word is drawn the way the Omarchy wordmark is drawn -- as block art, in the
FIGlet font Omarchy sets its own name in -- at about twice the height a plain
word would be. `osd.ascii = false` gives you the plain word instead, and so does
an action label with a digit or a punctuation mark in it: that font has letters
and spaces only, and announcing half a label would be worse than announcing a
plain one. Either way the text is set in the Omarchy font unless `osd.font`
names another.

Where it appears follows the overlay: `osd.position` (`top`, `center`,
`bottom`) is relative to the focused window in `window` scope and to the screen
in `monitor` scope, so the word is always on the thing you are aiming at.

It never eats a click: its input region is empty, so the pointer passes straight
through it, and it takes no keyboard focus.

With the shipped defaults (hints / window / single) the eight chords come out
as below; set your own defaults and the whole table moves with them.

| Chord | MODE | SCOPE | LIFETIME |
| --- | --- | --- | --- |
| `SUPER + ;` | hints | window | single |
| `SUPER + SHIFT + ;` | hints | monitor | single |
| `SUPER + ALT + ;` | grid | window | single |
| `SUPER + SHIFT + ALT + ;` | grid | monitor | single |
| `SUPER + CTRL + ;` | hints | window | continuous |
| `SUPER + CTRL + SHIFT + ;` | hints | monitor | continuous |
| `SUPER + CTRL + ALT + ;` | grid | window | continuous |
| `SUPER + CTRL + SHIFT + ALT + ;` | grid | monitor | continuous |

## Scrolling: `SUPER + '`

`SUPER + '` turns the keyboard into a mouse wheel wherever the pointer already
is. No overlay comes up; the pointer wears a mark instead, which lurches the
way each notch goes and names the modifiers it is holding. It stays on until
`Escape`.

| Key | Does |
| --- | --- |
| arrows, `hjkl`, `wasd` | one notch of the wheel that way; hold to keep going |
| hold `Ctrl`, `Alt` or `Shift` | the wheel with it held -- `Ctrl` zooms a browser a level per notch |
| `Escape` | stop scrolling, and let go of anything held |

Modifiers are simply held, as with a real wheel. To scroll somewhere else,
press `/` in the overlay: it moves the pointer to what you pick and then
scrolls there, and any modifiers you had toggled on in the overlay stay held
for the whole scroll. Needs the wl-kbptr this plugin builds.

## Bring your own keybinding

`./install.sh` asks before it touches `~/.config/hypr/hyprland.lua`, because
one `require(...)` line is the whole integration and it claims more than just
`SUPER + ;`: the same file defines the Hyprland submap that makes every key
*inside* the overlay work (labels, `Tab`, `F1`, drag, hold, the lot), and it
also takes over `CTRL + ALT + DELETE` so a stuck overlay always has a way out.
Say no, or install non-interactively, and none of that is touched — but that
means the overlay does not respond to any key yet, not even one you bind
yourself, because the submap it needs does not exist in Hyprland's config
until that line is there.

`imthemousenow` and its flags (see [The command line](06-command-line.md))
still run fine from a terminal either way — try `imthemousenow --mode grid`
— which is enough to confirm the install worked before you decide about keys.

When you're ready:

- `./install.sh --keybinds` adds the include without asking again, or
  `./install.sh --no-keybinds` skips the prompt and leaves it out.
- To bind something other than `SUPER + ;`, don't copy the chord logic into
  your own config — add the include (either flag above, or by hand: see
  `REQUIRE_LINE` in `install.sh`) and then override just the binding you want
  changed, as the top of `hypr/imthemousenow.lua` describes: call
  `hl.unbind("SUPER + SEMICOLON")` in `~/.config/hypr/bindings.lua`, then bind
  your own key to `imthemousenow` (or to `imthemousenow --flip mode`, etc.).
  The submap and everything it wires up for you come along either way, so the
  overlay itself keeps working — only which key opens it changes.

---

[← The four choices](01-the-four-choices.md) · [Manual contents](README.md) · [Inside the overlay →](03-inside-the-overlay.md)
