# Colours and opacity

## Colours

Five ACTIONs need five tints you can tell apart, and only one of them is chosen:
`left-click` is your theme's accent, because the ordinary overlay should look
like the rest of the desktop rather than announcing itself. The other four are
turned off it, 72° apart around the colour wheel — so a new theme repaints the
whole set, and no hue is ever picked by hand.

The turning happens in **OkLCh**, not HSL, and that is the part that matters. In
HSL, equal hue steps are not equal steps to an eye: at one lightness number,
yellows and cyans come out glaring while blues sink away, so a wheel divided
evenly there gives you a set where some members shout and others get missed.
OkLCh is built on a model of human vision, so holding lightness and chroma still
and moving only the hue produces colours of genuinely equal weight — which is
what a set of signal colours has to be, none louder than the rest.

Two guard rails, both measured across all 22 shipped themes rather than guessed:

- Four themes have an accent with almost no colour in it (`vantablack` and
  `white` are grey; `solitude` and `last-horizon` nearly so). Rotating the hue
  of a grey gives five greys, so the derived four get a floor of chroma even
  when the accent has less. They stay muted, and `left-click` keeps the accent
  exactly as the theme wrote it — a monochrome theme still looks monochrome
  until you switch ACTION, which is the moment you need telling.
- sRGB is not a cylinder: the chroma available at a hue collapses as lightness
  rises. Two themes (`hackerman`, `kanagawa`) have accents up at a lightness
  where no hue can hold enough chroma to separate five of them, so the derived
  four are pulled down far enough to buy it back.

The result: every shipped theme separates its five by at least 0.096 in Oklab,
where 1.0 is black to white. `tests/action-colors.sh` asserts it, so a new theme
cannot quietly break it.

To repaint everything, override the one line in your own copy of
`~/.config/omarchy/themed/wl-kbptr.conf.tpl`. To pin a single ACTION, name it in
`config.toml` — anything written by hand is left alone and only the gaps are
derived:

```toml
[imthemousenow.action.drag]
color = "#9a9af1"
```

## Opacity, per MODE

wl-kbptr has no opacity setting — opacity is the alpha on each colour, and each
MODE draws with different ones. `[imthemousenow.opacity]` is one number per MODE
over the top of that:

```toml
[imthemousenow.opacity]
hints = 0.6     # see more of the page through the hints
grid = 1.2      # dim harder while aiming at a grid
default = 1.0   # any MODE without a line of its own
```

1.0 is the theme's own colours; below that the overlay gets more transparent,
above it more solid, clamped at fully opaque. It scales the *backgrounds* only
— the dim over everything unselectable, and the fill behind each label or
bisect area. Labels, borders and the pointer keep the alpha the theme gave them,
so an overlay you turned right down is see-through rather than unreadable.

The arithmetic happens on whatever colours are in effect, theme included, and
arrives at wl-kbptr as per-run `-o` overrides — which is also what lets `hints`
and `windows` differ even though both draw with `[mode_floating]`. A colour you
set by hand in `config.local` is applied after, and is never scaled.

For the other kind of transparency — the whole overlay, only while a key is
held — see [Seeing through the overlay](03-inside-the-overlay.md#seeing-through-the-overlay-hold-space).

See what a MODE actually resolves to:

```bash
imthemousenow-config opacity hints    # the override lines it will pass
imthemousenow --mode hints --dry-run  # the whole wl-kbptr command
```

---

[← The bar widget](08-bar-widget.md) · [Manual contents](README.md) · [Popup-safe mode →](10-popup-safe-mode.md)
