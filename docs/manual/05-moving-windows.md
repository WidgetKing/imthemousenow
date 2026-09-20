# Moving and swapping windows

## Swapping two windows: `Tab`

In `window` SCOPE, `Tab` swaps the window the overlay is on with another one —
and the other one is chosen the way everything else here is chosen, by naming
it. `Tab` opens a picker with one label per window on screen; pick one and the
two windows exchange places, with the overlay coming back on the window you
started from, now where the other one was.

The picker is an ordinary overlay — `--mode windows`, which you can also ask
for directly when the detector keeps missing something and a whole window is
the target you want. It is tinted, like `;` and `:` are, because it is not the
overlay you opened.

**The window you are swapping is not among the labels.** Swapping a window with
itself is nothing happening, so it is not offered — every label in the picker
is a swap that does something.

Escape in the picker returns you to the overlay you pressed `Tab` in, rather
than ending the run — it abandons the detour, not the session. Escape there
closes the overlay as it always has.

The picker labels what is on screen on the monitor it is drawn over: that
monitor's active workspace, plus the scratchpad when the scratchpad is up.
Windows sitting on its other workspaces keep their geometry but are not on
screen, so labelling them would be labelling nothing — and drawing them over
the windows you can see is what makes a picker unreadable.

**The window you want does not have to be on this screen.** The arrow keys walk
the picker to the monitor that way — `→` to the one on the right, `↑` to the
one above, by where the monitors actually are rather than by index — and the
labels are rebuilt from the windows there. Pick one and the two windows
exchange places across the boundary. The digits do nothing while you are
picking: a workspace change would swap the labels out from under a half-made
choice.

| Key | Does, in the picker |
| --- | --- |
| a label | swap with that window |
| `←` `→` `↑` `↓` | look at the monitor that way |
| `1` … `9` | nothing |
| `Escape` | back to the overlay you pressed `Tab` in |

Nothing happens in `monitor` SCOPE, where the overlay is not drawn over any one
window, or when there is no other window anywhere to swap with.

## Moving what is under the overlay

The digits and the arrow keys move the world underneath the overlay, which is
then rebuilt around where things ended up — so you never have to close it to go
there. What they move depends on SCOPE.

When SCOPE is `monitor`, the overlay is a whole screen, so they move the screen:

| Key | Does |
| --- | --- |
| `1` … `9` | switch to that workspace |
| `←` / `→` | previous / next workspace on this monitor |
| `↑` / `↓` | previous / next monitor, left to right, wrapping |

(During the drop pass of a drag all four arrows change monitor instead, by
direction, and the digits do nothing — see [Dragging](04-dragging.md).)

When SCOPE is `window`, the overlay is one window, and moving the view would be
moving away from the thing you are aiming at — so the same keys move that
window instead, exactly as they do outside the overlay:

| Key | Does | Same as |
| --- | --- | --- |
| `1` … `9` | send the window to that workspace, and follow it there | `SUPER + SHIFT + n` |
| `←` `→` `↑` `↓` | move the window within the workspace | `SUPER + arrow` |

Tiled windows move through the layout, floating ones across the screen. With no
window to move — an empty workspace — the keys do nothing.

## Resizing the window: `-` `=` `_` `+`

In `window` SCOPE, the four keys Omarchy already resizes with resize the window
the overlay is drawn over, in the same directions and by the same 100px step:

| Key | Does | Same as |
| --- | --- | --- |
| `-` | expand the window left | `SUPER + -` |
| `=` | shrink the window left | `SUPER + =` |
| `_` | shrink the window up | `SUPER + _` |
| `+` | expand the window down | `SUPER + +` |

The step is `resize.step` in the config. Nothing happens in `monitor` SCOPE,
where the overlay is not drawn over any one window, or with no window to
resize. Like everything else that changes the world under the overlay, each
press costs the flicker of a rebuild and discards anything you had typed.

All of them cost the same flicker as `;`, for the same reason, and anything you
had already typed is discarded. In `monitor` SCOPE, `↑` / `↓` do nothing at all
with one monitor.

`;` reaches us rather than wl-kbptr because it is a compositor binding inside a
Hyprland submap that exists only while the overlay is up. Everywhere else, and
at every other moment, `;` is an ordinary semicolon. The submap is reset
however the overlay exits, including a crash, and `CTRL + ALT + DELETE` resets
it too. The digits and arrows live in that same submap, so they too are
ordinary keys the moment the overlay is gone.

---

[← Dragging and holding](04-dragging.md) · [Manual contents](README.md) · [The command line →](06-command-line.md)
