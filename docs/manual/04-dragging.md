# Dragging

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

---

[← Inside the overlay](03-inside-the-overlay.md) · [Manual contents](README.md) · [Moving and swapping windows →](05-moving-windows.md)
