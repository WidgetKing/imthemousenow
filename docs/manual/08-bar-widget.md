# The bar widget

`install.sh` adds a **Pointer** widget to the Omarchy bar, beside the ones for
sound, Wi-Fi and battery, so the settings worth changing are reachable without
opening a config file at all. Click it for the panel; right-click it to fire the
chord itself.

It is an ordinary third-party shell plugin: a `manifest.json` and its QML in
`~/.config/omarchy/plugins/imthemousenow/`, which is the directory the shell
walks looking for them. `install.sh` puts them there and runs `omarchy plugin
enable`; `uninstall.sh` takes the widget off the bar before removing the files,
so you never get a gap that only hand-editing `shell.json` explains.

To manage it yourself:

```bash
omarchy plugin enable imthemousenow --section right   # put it on the bar
omarchy plugin disable imthemousenow                  # take it off
omarchy bar move imthemousenow <section>              # move it
omarchy-shell imthemousenow toggle                    # open it from a script
```

Everything in the panel goes through `imthemousenow-config`, so the widget and
the config file are the same settings seen twice. It reads the fully merged
value -- not just what is literally in your own file -- with a single
`imthemousenow-config env` when it opens, and a write lands in
`~/.config/omarchy/imthemousenow/config.toml` with your comments left alone. A
value the config program refuses is reported in the panel and the real value
comes back, rather than the panel and the file quietly disagreeing.

The panel covers the four axes of the default chord, overlay opacity, the
action word and its position and size, and the three switches. Everything else
-- the timing constants, the MODE definitions, per-MODE opacity -- is behind
**Edit config…**, which is why that button is not optional. **Check** validates
every layer in a floating terminal.

Two rows hide themselves rather than lying: **Popup-safe overlay** appears only
when the installed wl-kbptr is the one this plugin builds (the same question
`bin/imthemousenow` asks before turning it on), and the action word's position
and size appear only while the word itself is on.

The panel is fully keyboard-driven, like every other Omarchy bar panel: `j`/`k`
walk the rows, `h`/`l` move between chips or nudge a slider, Enter commits,
`e` and `c` are Edit and Check, and Escape closes.

Earlier versions put these settings in the Omarchy menu instead. A menu row can
only ever be a toggle or a pick-one-of-N — there is no text box and no slider —
so opacity was three presets pretending to be a range and every real number was
behind "Edit Config…". Upgrading removes those rows from
`~/.config/omarchy/extensions/omarchy-menu.jsonc`; only what is between the
markers goes, and `bin/imthemousenow-menu remove` is still there to do it by
hand.

---

[← Configuration](07-configuration.md) · [Manual contents](README.md) · [Colours and opacity →](09-appearance.md)
