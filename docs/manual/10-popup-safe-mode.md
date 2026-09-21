# Popup-safe mode

`popups.keep_open`, and experimental.

Opening the overlay closes a context menu or a browser extension popup, which
is often the very thing you wanted to click. That is the compositor, not the
app: a layer surface that asks for keyboard focus makes Hyprland drop the grab
the popup holds, and the client is told its popup is done.

Turn `popups.keep_open` on and the overlay asks for no keyboard focus at all.
Its keys come from compositor bindings instead — the same mechanism that
already gets `;`, `F5` and the arrows to it — relayed through a file wl-kbptr
reads, so the menu underneath keeps its focus and stays open to be aimed at.

```toml
[imthemousenow.popups]
keep_open = true
```

Experimental, and off by default. What to know before turning it on:

- It needs the wl-kbptr this plugin builds (`./install.sh` applies
  the fork's "Take keys from a channel" commit). With a stock wl-kbptr the
  setting is ignored and nothing changes.
- Every key the overlay uses is a binding, in its own submap. Plain keys it
  does not use are swallowed rather than reaching the window underneath;
  chords are not, so `CTRL + T` still opens a tab in the browser you are
  aiming at.
- Everything else is the same overlay: same modes, same labels, same `;`, same
  Escape.

---

[← Colours and opacity](09-appearance.md) · [Manual contents](README.md) · [Getting unstuck →](11-troubleshooting.md)
