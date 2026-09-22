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

The switch happens in place: the overlay stays up, re-tints, and keeps anything
you had already typed. (On a wl-kbptr older than this plugin's build it is put
back up instead, a brief flicker that discards what you had typed.)

All three are toggles — press the same key again to go back — and all three are
one-offs: after the pointer lands, the overlay returns to whatever ACTION the
chord asked for, even in a continuous lifetime. So a right click or a bare move
costs one extra keypress and neither changes what the next click does.

## Double click: press it again

Make the selection, then press the very key that made it a second time.

Which key that is falls out of the MODE, and it is the same sentence either
way — *press again what you just pressed*:

| MODE | The key that selects | Double click |
|---|---|---|
| `grid` | `Space` or `Return` commits the area | `Space`, `Space` |
| `hints` | the last letter of the label | hint `bd` → `b`, `d`, `d` |

So the hint `xyz` is double clicked by typing `x`, `y`, `z`, `z`, and there is
nothing new to learn in the second mode once you know it in the first.

The first click goes out the instant you commit, exactly as it always did.
Nothing is held back waiting to see whether a second one is coming — the first
click of a double click *is* a single click, and a mouse does not know which
one it is making either. So a double click costs nothing that a single click
does not, and this adds no delay to anything.

What is on screen while the second press is possible is not the overlay: it
would hide the thing you just clicked, which is the thing you are deciding
about. The overlay goes and the spot you clicked is marked instead, for
exactly as long as a second press would land: a patch of **LCD pooling**, the
chunky rainbow bruise a thumb leaves pressing into a screen, in the theme's
own colours. The point itself is left clear, so what you clicked can still be
read; it is everything around it that goes wrong. Every click leaves one, a
right click as well, so it is also simply how you see where a click went. The
pointer wears the same thing during a [hold](04-dragging.md), and for the same
reason — the desktop looks normal while the keyboard does not mean what it
usually does. `[imthemousenow.pool]` sets its size and chunkiness and its
`style`: `pool` (the ring), `patchy` (the ring with big chunks dead), `lines`
(colour bleeding down the screen in columns), `cross` (a dead row and column
through the point), or `random` for a different one every click. Each keeps
the point itself clear and centred. `enabled = false` turns it off, and a
click then leaves no mark.

**The catch.** While that mark is up the overlay still has the keyboard, so a
key typed in that instant is eaten rather than reaching what you clicked. Any
key that is not the committing one closes the window immediately, so it is one
keystroke at worst — but if you click into a text field and start typing in the
same breath, that is where the first letter went. Set `ms = 0` under
`[imthemousenow.double_click]` to turn the whole thing off and never pay it.

**How long you have** comes from the desktop rather than from this plugin:

```
gsettings get org.gnome.desktop.peripherals.mouse double-click
```

That is the number the applications being clicked are measuring against, so
following it is the point — one setting, in the place the desktop already keeps
it. A small guard comes off it, because the second click goes out when you
press the key rather than when the window closes, and a press right at the edge
would land just past it and read as two separate clicks. Put a number in place
of `system` to fix the window yourself.

Only `left-click` arms it. A double right click is not a thing anything
listens for, and `move`, `drag` and `hold` have no click to double. It also
needs the `wl-kbptr` this plugin builds — on a stock one the setting is inert
and everything else works as before. See
[Configuration](07-configuration.md).

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

## Retuning the overlay: `SHIFT`, `ALT` and `CTRL`

**SHIFT, ALT and CTRL retune the overlay**, tapped on their own with nothing
else held, on the command side of the keyboard (the left, unless
`keyboard_modifier_side` says otherwise). They flip the same axis they flip in the chords, so there is nothing new
to remember:

```
SHIFT   SCOPE      window  <->  monitor
ALT     MODE       hints   <->  grid
CTRL    LIFETIME   single  <->  continuous
```

`CTRL` changes nothing on screen: it decides what happens after the next
selection, so there is nothing to relaunch.

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

## Clicking with modifiers held

The modifier keys on the two sides of the keyboard do different jobs inside
the overlay. The **command side** (left, as shipped) is the section above:
`SHIFT` flips SCOPE, `ALT` flips MODE, and `CTRL` flips LIFETIME between
`single` and `continuous`. `SUPER` there does nothing yet.

The **modifier side** (right, as shipped) holds modifiers down for the click.
Tap `CTRL` there and the next click is a Ctrl click; tap it again and it is
not. They stack: tap `CTRL`, `ALT` and `SHIFT` and the click is made with all
three held. The action word comes up to say what is on, always in the order
`Ctrl + Alt + Shift + Super`, whatever order you tapped them in — `CTRL + ALT +
RIGHT` — and comes up again without one when you take it off.

- They last for **one press**. In a continuous lifetime the next click starts
  plain, and every overlay starts with none.
- Switching ACTION keeps them, and the word for the new ACTION shows them.
- A **drag** carries them from the pick-up pass into the drop pass, where you
  can add more or tap one off again; whatever is on at the drop is held for
  the whole press, travel and release.
- A **hold** holds them for as long as the button is down.
- A **double click** holds them for both clicks.
- A **move** presses nothing, so the toggles do nothing there.

Toggling one relaunches a clicking overlay, with the same flicker as `SHIFT`
and `ALT`, because the click is told its modifiers when it starts.

To swap the sides — once the right hand is used to it, the left is the more
natural place for held modifiers — set it in `config.toml`:

```toml
[imthemousenow]
keyboard_modifier_side = "left"
```

Needs the wl-kbptr this plugin builds, which holds the modifiers with a
virtual keyboard on the same seat. On a stock build a toggle is refused with a
notification rather than clicking without what you asked for.

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
same flicker a switch of ACTION used to, and anything you had already typed is discarded.

---

[← Keybindings](02-keybindings.md) · [Manual contents](README.md) · [Dragging and holding →](04-dragging.md)
