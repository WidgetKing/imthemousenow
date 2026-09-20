# imthemousenow — the manual

Driving the mouse pointer from the keyboard on [Omarchy](https://omarchy.org).

Everything this plugin does, in the order it is worth learning. If you have
just installed it, read [The four choices](01-the-four-choices.md) and
[Keybindings](02-keybindings.md) and you can stop there — the rest is here for
when you want it. Inside any overlay, `F1` shows the keys that are live at that
moment, which is faster than any page here.

## Using it

1. [The four choices](01-the-four-choices.md) — MODE, SCOPE, ACTION, LIFETIME:
   the whole vocabulary, and why there are no named modes to memorise.
2. [Keybindings](02-keybindings.md) — `SUPER + ;`, the three modifiers that
   flip one axis each, and the word that names the ACTION you moved into.
3. [Inside the overlay](03-inside-the-overlay.md) — typing a label, switching
   ACTION with `;` `:` `'` `"`, holding `Space` to see through it, retuning it with
   `SHIFT` and `ALT`, and the key sheet on `F1`.
4. [Dragging and holding](04-dragging.md) — `'` for two questions and one
   press, `"` for a button held down while you fly the pointer by hand.
5. [Moving and swapping windows](05-moving-windows.md) — `Tab` to swap two
   windows, the digits and arrows, and resizing from inside the overlay.
6. [The command line](06-command-line.md) — the four choices as flags.

## Setting it up

7. [Configuration](07-configuration.md) — the config file, what it inherits
   from wl-kbptr, and `imthemousenow-config`.
8. [The bar widget](08-bar-widget.md) — the Pointer widget, and the settings
   that never need a text editor.
9. [Colours and opacity](09-appearance.md) — where the six ACTION tints come
   from, and how much of the screen an overlay hides.
10. [Popup-safe mode](10-popup-safe-mode.md) — aiming at a context menu without
    closing it. Experimental.

## When something is wrong

11. [Getting unstuck](11-troubleshooting.md) — a stuck overlay, and the panic
    key.
12. [How it is built](12-how-it-is-built.md) — why wl-kbptr is built from a
    pinned commit, what the patches add, and what lives where in the repo.

## Beyond the manual

- [Design notes](../design-notes.md) — what was verified against a real machine,
  and where the implementation departs from the plan.
- [Lessons learned](../lessons-learned.md) — what it cost to find out:
  wl-kbptr internals, Hyprland's Lua config surface, and which decisions here
  are load-bearing.
- [Installation, privacy and security](../../README.md) — the read-me.
