# Getting unstuck

Only one overlay runs at a time. wl-kbptr grabs the keyboard, so a second
instance would stack an unreachable overlay beneath the new one and lock the
session out; pressing any pointer chord while one is up is a no-op instead.
`imthemousenow --stop` closes whatever is running, including an overlay left
behind by a crash.

`CTRL + ALT + DELETE` is also a way out: the plugin rebinds it to
`imthemousenow-panic`, which dismisses any overlay and then runs Omarchy's own
action for that key (`omarchy-hyprland-window-close-all`), so the stock
behaviour is preserved rather than replaced. Hyprland keybindings still fire
while wl-kbptr holds the keyboard, which is what makes this reachable at all.

Both of those need `hypr/imthemousenow-submap.lua` loaded, which `./install.sh
--keybinds none` deliberately skips. See
[Bring your own keybinding](02-keybindings.md#bring-your-own-keybinding) for
what that trades away before you pick it.

---

[← Popup-safe mode](10-popup-safe-mode.md) · [Manual contents](README.md) · [How it is built →](12-how-it-is-built.md)
