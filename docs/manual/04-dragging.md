# Dragging and holding

Two ways to move something with the button down. `'` is a drag: say both ends
and watch it happen. `"` is a hold: take hold of one end and fly the pointer
yourself, watching the thing move as you go.

## Dragging

`'` starts a drag, and a drag is two questions rather than one.

```
'          DRAG   aim at the thing to pick up, land on it
           DROP   the overlay comes back; aim at where it goes
                  press, travel, release
```

The first pass only moves the pointer onto what you are picking up — nothing is
pressed yet. The second pass asks the other half of the question, and only when
both ends are known does the button go down, travel to the drop point and come
back up. Nothing is ever held while you are still deciding, so `;`, `:`, `'` and
Escape all abandon a half-finished drag and leave the desktop exactly as it was.

The travel is not instant, and cannot be. A client reads drag-and-drop out of
the stream of motion events under a held button; one jump from start to finish
gives it a single event to infer everything from, and toolkits that arm on a
movement threshold, autoscroll on dwell, or animate a drop target never get the
chance. `action.drag.duration_ms` is how long the pointer takes to cross —
300ms by default. Raise it if an application keeps missing the drop.

The drop pass is drawn over the whole monitor the drag picked up on, whatever
SCOPE says: you are usually dropping onto something other than the window you
picked up from. It uses the same MODE the drag started in; set
`action.drag.drop_mode` to `grid` to always drop in the grid, which is the one
MODE that can reach a pixel no hint names — blank canvas, or the gap between
two list items.

A drop can be on another monitor. The drop overlay starts on the monitor the
drag picked up on, and the arrow keys carry it to the screen that way — `→` to
the one on the right, `↑` to the one above, by where the monitors actually are
rather than by index. Pick a target there and the pointer walks the whole path,
across the boundary, with the button held the whole way.

During a drop pass, and only there, the arrows mean monitors and nothing else,
and the digits do nothing at all:

| Key | Does, during a drop |
| --- | --- |
| `←` `→` `↑` `↓` | aim at the monitor that way |
| `1` … `9` | nothing |

Mid-drag, "left" means the screen on the left far more often than it means the
workspace before this one, and one key that might mean either leaves you unsure
which you just did — while one end of a path is already held. So the ambiguity
is removed rather than explained: no key changes workspace while a drag is
half-finished.

Drag needs the `wl-kbptr` this plugin builds (`pkg/0003-walk-a-path-*.patch`
and `pkg/0004-Say-a-drag-path-*.patch`);
with a stock one the chord says so rather than half-running.

## Holding

A drag has to know where it is going before it starts. Plenty of things cannot
be said that way: a scrollbar pulled until the page looks right, a window edge
sized by eye, a selection swept across text you are reading as you go. Those
need the button already down while you decide.

`"` — the same key as `'`, with Shift — is that. One pass aims at the thing to
take hold of; the button goes down there and stays down, and from then on you
steer the pointer by hand:

| Key | Does, during a hold |
| --- | --- |
| `←` `→` `↑` `↓`, `wasd`, `hjkl` | move the pointer, button still down |
| `Shift` + any of those | move in big steps |
| `Space`, `Return`, `Escape` | let go of the button |

Three sets of direction keys because there is no one right set, and no key has
another meaning to lose: a hold reads the whole keyboard and nothing else is
running. They repeat, so a held key is a pointer that keeps going — 40px a step
by default, and five of those with Shift. One number sets both:
`action.hold.step`, or the Hold slider in the bar widget.

**There is no overlay during a hold.** That is the point of it: you are watching
the thing you are moving, not a grid of labels drawn over it. So the only sign
that a button is down is the pointer itself, which wears a pulsing halo for as
long as the hold lasts — `action.hold.halo_size` is how big, and its colour is
the hold ACTION's own.

Every key is a compositor binding while a hold is on, and the ones that are not
listed above are swallowed rather than passed through: a mistyped key must not
be typed into the thing you are dragging. `Ctrl+Alt+Del` still works, and still
lets go of the button — the press lives in one process that releases it however
it ends, including under a signal, so nothing can leave the desktop with a
button down.

A hold can cross a monitor boundary: the pointer is steered in layout
coordinates, and the halo follows it onto the next screen.

Hold needs the `wl-kbptr` this plugin builds
(`pkg/0006-Hold-a-button-*.patch`); with a stock one the chord says so rather
than aiming at something it cannot then take hold of.

---

[← Inside the overlay](03-inside-the-overlay.md) · [Manual contents](README.md) · [Moving and swapping windows →](05-moving-windows.md)
