# Inside the overlay

In `hints`, type a label and it clicks. In `grid`, type a label to pick a cell,
then the home row (`a s d f` / `j k l m`) halves it until the pointer is where
you want it; `g`, `h` and `b` commit with a left, right or middle click.

**`;`, `:`, `'` and `"` switch ACTION**, in either mode, at any point before
you commit:

```
;   right click        the overlay is tinted
:   move, no click     a different tint
'   drag               a different tint again
"   hold               and one more: the button stays down
```

`;` and `:` are the same physical key, which is the point: one to click
differently, one to not click at all. The tint is what tells you which you are
in — the tints are not fixed hues, `left-click` being your theme's accent and
the rest turned off it. See [Colours](09-appearance.md#colours).

All three are toggles — press the same key again to go back — and all three are
one-offs: after the pointer lands, the overlay returns to whatever ACTION the
chord asked for, even in a continuous lifetime. So a right click or a bare move
costs one extra keypress and neither changes what the next click does.

## Seeing through the overlay: hold `Space`

The overlay covers the thing you are aiming at. That is the whole point of it
and also its one blind spot: the usual way a selection goes wrong is a label
landing on top of the word that would have told you which target you wanted.

**Hold `Space` and the overlay fades almost away.** Let go and it comes back.
Nothing moves and nothing is selected, so the labels are exactly where they
were once you can read what is underneath them — look, let go, type the label.

```toml
[imthemousenow]
peek_alpha = 0.1   # what it fades to; 1 turns the peek off
```

This is not [per-MODE opacity](09-appearance.md#opacity-per-mode). That one is how the overlay
looks the whole time it is up, and it scales the theme's colours so that labels
stay readable at any setting. The peek is the opposite: the *entire* surface —
dimming, labels, borders, the bisect pointer — faded at once, for as long as
the key is held, precisely so that none of it is in the way.

**Not available in the second half of a `grid` selection.** Once a grid reaches
bisect, `Space` commits the area the way `Return` does, and it keeps that job.
`hints` has no bisect in it, so the peek is there throughout; in `grid` you get
it while picking the cell and lose it once you start halving. A key that dims
sometimes and clicks other times would be worse than one that only dims where
it can.

Needs the wl-kbptr this plugin builds. On a stock build the option is not
passed through at all, and deliberately: wl-kbptr rejects an entire config file
over one option it does not recognise, so shipping this unconditionally would
not cost you the peek — it would cost you every chord. `bin/imthemousenow` asks
the installed binary whether it knows the option and stays quiet if it does
not, the same way it gates `--drag` and the popup-safe overlay.

## Retuning the overlay: `SHIFT` and `ALT`

**SHIFT and ALT retune the overlay**, tapped on their own with nothing else
held. They flip the same axis they flip in the chords, so there is nothing new
to remember:

```
SHIFT   SCOPE   window  <->  monitor
ALT     MODE    hints   <->  grid
```

That is the whole point of the modifiers being one-axis-each: the overlay in
front of you can become the one you meant without closing it and re-chording.
Tapping either again flips back. A tap within 400ms of any other overlay key is
ignored, because releasing SHIFT is also how a chord like `:` ends
(`switch.tap_debounce_ms`).

The overlay is torn down and relaunched to do this, because wl-kbptr takes its
configuration at startup and cannot be reconfigured while it holds the
keyboard. You will see a flicker, and anything you had already typed is
discarded — the trade for being able to decide *after* seeing the overlay
rather than before.

## The keys, on screen: `F1`

Nothing here is printed on a key, and the overlay is invisible until one is
pressed — so the one thing you cannot work out by looking is what you are
allowed to press. `F1` writes it all down, and `Escape` puts it away.

The sheet is about the overlay you are actually in, not about the plugin: the
resize keys only appear in `window` SCOPE, `grid` names the home row and
`hints` does not, and in the middle of a drag it says outright that the digits
do nothing and that the arrows have changed meaning. A sheet that listed keys
which currently do nothing would be teaching the wrong thing.

It replaces the overlay for as long as it is up rather than covering it: it
reads its own keyboard and wl-kbptr is holding one. Dismissing it puts the
overlay back exactly as it was — same MODE, SCOPE and ACTION — so pressing `F1`
mid-selection costs you the letters you had typed and nothing else. Pressing
`F1` again closes it too.

In popup-safe mode the sheet takes no keyboard at all, for the same reason
nothing else in that mode does; `Escape` and `F1` reach it as compositor
bindings instead, and behave the same.

`?` is not a second way in, and that was tried: on a QWERTY keyboard the keysym
only exists while `SHIFT` is held, so the bind has to carry the modifier — and
`?` is not on `SHIFT` on every layout, so covering it properly means a pair of
binds whose correctness depends on the keymap. `F1` is the help key on every
keymap there is.

## Refreshing an overlay: `F5`

An overlay is measured once, when it opens — the window's geometry, and in
`hints` mode the regions found in one frame of the framebuffer. The screen does
not hold still for that: a page scrolls, a window resizes, a dialog opens, and
the labels go on naming where things used to be. `F5` rebuilds the overlay
against the screen as it is now, keeping MODE, SCOPE and ACTION. It costs the
same flicker as `;`, and anything you had already typed is discarded.

---

[← Keybindings](02-keybindings.md) · [Manual contents](README.md) · [Dragging and holding →](04-dragging.md)
