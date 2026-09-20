# The four choices

Every invocation is the same four independent choices. There are no modes with
names to memorise and no special cases — any combination is valid.

| | Options | |
| --- | --- | --- |
| **MODE** | `hints` · `grid` · `windows` | how targets are presented |
| **SCOPE** | `window` · `monitor` | where the overlay is drawn |
| **ACTION** | `left-click` · `right-click` · `move` · `drag` · `hold` | what happens when you land (`;` `:` `'` `"` switch it live) |
| **LIFETIME** | `single` · `continuous` | one selection, or until Escape |

**MODE** — `hints` labels what looks clickable: detected targets when the build
has OpenCV, open window rectangles when it does not. Typing a hint's label
clicks it, because the hint already identifies the target. `grid` labels a grid
of cells covering the area, then halves the chosen cell with the home row until
the pointer is exactly where you want it — slower, but it never misses a target,
because it does not try to guess where the targets are. `windows` labels whole
windows, one label each — what `Tab` opens to pick a window to swap with, and
useful on its own when a whole window is the thing you are aiming at.

**SCOPE** — `window` confines the overlay to the focused window, so the labels
stay short and you aren't offered the rest of the desktop. `monitor` covers the
whole focused screen. Either way the digits and the arrow keys steer without
closing the overlay: they move the screen under a `monitor` overlay, and the
window under a `window` one.

**ACTION** — what the pointer does on arrival. `move` places the pointer and
leaves it there, clicking nothing. `drag` asks twice — once for the thing to
pick up, once for where it goes — and only then presses, travels and releases.
`hold` asks once, puts the button down there and leaves it down while you fly
the pointer with the arrows, `wasd` or `hjkl` — for everything a drag cannot
say in advance, like a scrollbar pulled until the page looks right. This is the
one axis you do not have to decide up front: `;`, `:`, `'` and `"` switch it
while the overlay is on screen, which is the only moment you can actually see
what you are aiming at.

**LIFETIME** — `single` clicks once and gets out of the way. `continuous`
reopens after every click, so a burst of clicking is one invocation; Escape
ends it. Targets are recomputed every pass, so it follows windows that move,
open or close between clicks.

---

[Manual contents](README.md) · [Keybindings →](02-keybindings.md)
