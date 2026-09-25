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

What used to be one file, `hypr/imthemousenow.lua`, is two:

- `hypr/imthemousenow-submap.lua` is the overlay itself — every key it reads
  while it is up, the panic key, and nothing that opens it.
- `hypr/imthemousenow.lua` is two entry points, `SUPER + ;` (and its chords)
  and `SUPER + '`, plus a `require` that pulls the submap file in underneath
  them.

`./install.sh` asks which of three ways to wire this into
`~/.config/hypr/hyprland.lua`, or takes it as `--keybinds full|submap|none`:

| Choice | Gets you | Pick it when |
| --- | --- | --- |
| `full` (default) | Both files. `SUPER + ;` and everything above work immediately. | You want the shipped keys. |
| `submap` | Just `hypr/imthemousenow-submap.lua`. The overlay, the panic key and Escape all work; nothing opens the overlay for you. | You want your own entry key — bind it to `imthemousenow` (or `imthemousenow --flip ...`, same as the chords do) in `~/.config/hypr/bindings.lua`. |
| `none` | Neither file. | You are going to reference `hypr/imthemousenow-submap.lua` from your own Hyprland config in your own way. |

Either `full` or `submap` gets you a *working* overlay — the panic key
(`CTRL + ALT + DELETE`) lives in the submap file, not the entry one, precisely
so that choosing `submap` does not cost you the way out of a stuck overlay.
`imthemousenow` still runs from the CLI under every choice; what changes is
only whether anything is listening for a key to launch it.

**`none` needs a warning `install.sh` also prints.** `[imthemousenow.popups]
keep_open` ships **on**, and in that mode the overlay asks Hyprland for no
keyboard focus of its own — every key it reads, including Escape, arrives as a
compositor bind from the submap file, relayed through a file it watches. With
no submap loaded there is nothing to do that relaying: an overlay opened this
way cannot be reached by the keyboard *at all*, not even to cancel it. If you
pick `none` and still intend to launch `imthemousenow` yourself, either
`require("omarchy.plugins.imthemousenow.hypr.imthemousenow-submap")` from your
own config (which is the `submap` choice, just written by hand) or set
`keep_open = false` under `[imthemousenow.popups]` first — see
[Popup-safe mode](10-popup-safe-mode.md).

To override one binding rather than dropping a whole file, keep the `full` or
`submap` require and call `hl.unbind("SUPER + SEMICOLON")` (or whichever bind)
in `~/.config/hypr/bindings.lua` before binding it yourself — see the comment
at the top of `hypr/imthemousenow.lua`. Hand-copying the submap's logic
instead of requiring it is the one thing to avoid: it will drift out of step
with this plugin the first time either side changes.

---

[← The four choices](01-the-four-choices.md) · [Manual contents](README.md) · [Inside the overlay →](03-inside-the-overlay.md)
