-- imthemousenow: keyboard-driven pointer control.
--
-- Loaded from ~/.config/hypr/hyprland.lua via:
--   require("omarchy.plugins.imthemousenow.hypr.imthemousenow")
-- install.sh adds that line, guarded by a marker comment.
--
-- Override any of these in ~/.config/hypr/bindings.lua by calling
-- hl.unbind("SUPER + SEMICOLON") first, then binding it yourself.
--
-- One key, three modifiers, eight chords. SUPER + ; is the common case --
-- label what looks clickable in the window you are already looking at, click
-- once, get out of the way -- and each modifier flips exactly one axis:
--
--   SHIFT  flips SCOPE     window <-> monitor
--   ALT    flips MODE      hints  <-> grid
--   CTRL   flips LIFETIME  single <-> continuous
--
-- Flips, not fixed values: the bare chord is [imthemousenow.defaults], which
-- the Pointer widget in the bar writes, and a modifier asks for the other
-- value on its axis. Set the defaults to grid-on-monitor and SUPER + ; is
-- that, while SUPER + ALT + ; is still "the other mode".
--
-- SHIFT and ALT keep those meanings inside the overlay: tapped on their own,
-- they flip the same axis again, so the overlay you are looking at can become
-- the one you meant without closing it.
--
-- They compose, so you never memorise eight bindings: you memorise one, plus
-- what each modifier means. ACTION is not on a modifier because it is decided
-- after you can see the overlay, not before: `;`, `:`, `'` and `"` switch it.

-- The overlay is a layer-shell surface that must appear instantly: a fade or
-- slide makes the labels unreadable for the first frames.
hl.layer_rule({ match = { namespace = "wl-kbptr" }, no_anim = true, animation = "none" })

-- The ACTION announcement, for the same reason and one more: it is solid for a
-- quarter of a second before it starts fading, and the compositor's own fade-in
-- would spend most of that quarter second arriving. It does its own fade, on its
-- own schedule; Hyprland should just show it.
hl.layer_rule({ match = { namespace = "imthemousenow-osd" }, no_anim = true, animation = "none" })

-- Must match SUBMAP and SUBMAP_POPUPS in bin/imthemousenow.
SUBMAP_NAME = "imthemousenow"

-- The keyboard of a hold, which is not an overlay's. Must match SUBMAP_HOLD in
-- bin/imthemousenow-hold. See the submap itself, at the bottom of this file.
SUBMAP_HOLD = "imthemousenow-hold"
-- The keyboard of a scroll. Must match SUBMAP_SCROLL in bin/imthemousenow-scroll.
SUBMAP_SCROLL = "imthemousenow-scroll"

-- EXPERIMENTAL, off unless popups.keep_open is on. The same overlay, with its
-- keys arriving from here instead of from the keyboard.
--
-- Asking for keyboard focus is exactly what closes a context menu or a browser
-- extension popup: the compositor drops the popup's grab the moment a layer
-- surface with any keyboard interactivity maps, and the client is told the
-- popup is done. So in this submap the overlay asks for none, and every key it
-- needs is a binding here, appended to a file it reads. The keys never reach
-- the window underneath, which keeps its focus and its popup throughout.
SUBMAP_POPUPS = "imthemousenow-popups"

-- Must match SESSION_DIR in bin/imthemousenow-session.sh.
KEY_CHANNEL = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/imthemousenow/keys"

-- The keys the overlay itself reads: wl-kbptr's label symbols, plus the four it
-- treats as controls. Bash re-asserts the missing ones by name, so this list is
-- mirrored in bin/imthemousenow -- keep them in step.
--
-- `space` does two different things depending on where a selection has got to,
-- and both of them need it relayed. In `bisect` it commits the area, exactly as
-- `Return` does (`mode_bisect.c`, XKB_KEY_Return and XKB_KEY_space fall through
-- to the same case) -- and it is the key a hand already resting on the home row
-- reaches first. Everywhere else it is the peek: held down, the overlay fades
-- so the target under it can be read. wl-kbptr decides which; this just has to
-- deliver the key, because in popup-safe mode a key that is not relayed is a
-- key the overlay is not told about.
-- Escape is NOT in this list and is bound on its own in the popups submap
-- below: with the key sheet (F1) up there is no overlay for Escape to cancel,
-- and the sheet takes no keyboard in this mode -- taking it is precisely what
-- closes the popup the mode exists to keep open -- so Escape has to reach
-- imthemousenow-steer first and be relayed only when no sheet is showing.
RELAY_KEYS = { "comma", "BackSpace", "Return", "space" }
for byte = string.byte("a"), string.byte("z") do
  table.insert(RELAY_KEYS, string.char(byte))
end

-- The keys wl-kbptr needs to know were LET GO of, not just pressed. Only
-- `space`, and only because of the peek: holding it fades the overlay so the
-- thing underneath can be read, which means the overlay has to be told when
-- the hand comes off it. Every other key here is done the moment it is typed.
--
-- On the channel a release is the keysym name with `-` in front. A bare name
-- is still a press, so a wl-kbptr that predates the peek reads exactly what it
-- always did and simply never sees the release lines.
RELAY_RELEASE_KEYS = { space = true }

-- Append one keysym name for wl-kbptr to pick up. Opened per press: a handle
-- kept open across the overlay's life would have to be closed on every way an
-- overlay can end, and a missed close is a compositor holding a file open
-- forever. A failed open is a dropped keystroke, never an error dialog.
function imthemousenow_relay_key(name)
  local file = io.open(KEY_CHANNEL, "a")
  if file then
    file:write(name .. "\n")
    file:close()
  end
end

-- One relay bind, callable on its own: bin/imthemousenow re-asserts binds
-- Hyprland has dropped, and it can only do that through a name it can call.
function imthemousenow_relay_bind(name)
  hl.bind(name, function()
    imthemousenow_relay_key(name)
  end, {
    description = "Pointer: type " .. name .. " into the overlay",
  })
  -- Both halves come from this one function, so the re-assertion in
  -- bin/imthemousenow -- which can only call it by name -- restores a dropped
  -- key complete rather than press-only, which for `space` would be a peek
  -- that never ends.
  if RELAY_RELEASE_KEYS[name] then
    hl.bind(name, function()
      imthemousenow_relay_key("-" .. name)
    end, {
      release = true,
      description = "Pointer: let go of " .. name .. " in the overlay",
    })
  end
end

-- ACTION is switched from inside the overlay, and `;` is the key that opened
-- it. wl-kbptr holds the keyboard, so this cannot be a key wl-kbptr sees: it
-- has to be a compositor binding. A submap scopes it to exactly the overlay's
-- lifetime -- imthemousenow enters it on launch and resets it on exit, however
-- it exits -- so `;` keeps its ordinary meaning everywhere else. Keys with no
-- binding here, including every label and Escape, pass through untouched.
--
-- The same reasoning gives the overlay its own navigation. The thing you want
-- is often not where the overlay is, and leaving the overlay to go there costs
-- you the overlay. The digits and the arrows move the world under it instead,
-- and it is rebuilt around where things ended up -- what they move depends on
-- what the overlay is drawn over, monitor or window. wl-kbptr labels never use
-- digits or arrows, so nothing is taken away from it.
-- Everything an overlay binds whatever its submap: both of them get these.
local function overlay_binds()
  hl.bind("SEMICOLON", hl.dsp.exec_cmd("imthemousenow-steer action right-click"), {
    description = "Pointer: switch to a right click",
  })
  -- `:` is the same key with SHIFT, which keeps the two ACTION switches on one
  -- physical key: `;` to click differently, `:` to not click at all.
  hl.bind("SHIFT + SEMICOLON", hl.dsp.exec_cmd("imthemousenow-steer action move"), {
    description = "Pointer: switch to move without clicking",
  })

  -- `'` is the key next to `;`, which is where the other two ACTION switches
  -- live, and drag is the one that needs its own: `;` and `:` are two meanings
  -- of one physical key and there is no third modifier left on it that does
  -- not already mean something else in this submap.
  --
  -- Pressing it during the drop pass abandons the drag, and so do `;` and `:`.
  -- Nothing has been pressed at that point -- both passes only move the
  -- pointer, and the button is emitted after the second one -- so calling a
  -- drag off costs nothing and can leave nothing behind.
  hl.bind("apostrophe", hl.dsp.exec_cmd("imthemousenow-steer action drag"), {
    description = "Pointer: pick something up, then say where to drop it",
  })

  -- `"` is that same key with SHIFT, which puts the two halves of one idea on
  -- one physical key: `'` says both ends before anything is pressed, `"` says
  -- one end and keeps the button down while you steer the pointer to the other.
  -- Which is what a drag cannot do -- a scrollbar dragged until the page looks
  -- right, a window edge sized by eye -- because it has to know where it is
  -- going before it starts.
  --
  -- `SHIFT + apostrophe`, not `SHIFT + quotedbl`: Hyprland matches a bind
  -- against the keysym the key produces with NO modifiers applied, plus the
  -- modmask -- which is why `:` above is `SHIFT + SEMICOLON` rather than
  -- `SHIFT + colon`. Bound the other way the bind registers, shows up in
  -- `hyprctl binds`, and never fires. Measured, not assumed: `SHIFT +
  -- quotedbl` was registered first and `"` did nothing at all.
  hl.bind("SHIFT + apostrophe", hl.dsp.exec_cmd("imthemousenow-steer action hold"), {
    description = "Pointer: take hold of something and steer it by hand",
  })

  -- `/` puts the pointer somewhere and then scrolls there: the overlay picks
  -- the spot, and imthemousenow-scroll takes over from SUPER + ' onwards. Free
  -- in this submap, and the key a vim hand already knows as "go looking".
  hl.bind("slash", hl.dsp.exec_cmd("imthemousenow-steer action scroll"), {
    description = "Pointer: put the pointer there, then scroll",
  })

  -- The digits and the arrows are read by SCOPE, not fixed to one dispatcher:
  -- see the `arrow`/`digit` verbs in imthemousenow-steer. Over a whole monitor
  -- they move the view under the overlay; over a window they move that window,
  -- which is what SUPER + an arrow and SUPER + SHIFT + a digit do outside the
  -- overlay. Both keep you aiming at the thing you opened the overlay for.
  --
  -- The drop pass of a drag is the exception, and reads them both again: the
  -- arrows take the drop to the monitor that way, and the digits do nothing.
  -- Mid-drag, "left" means the screen on the left far more often than it means
  -- the workspace before this one, and a key that might mean either leaves you
  -- unsure which one you just did -- with one end of a path already held down.
  for workspace = 1, 9 do
    hl.bind(tostring(workspace), hl.dsp.exec_cmd("imthemousenow-steer digit " .. workspace), {
      description = "Pointer: go to workspace " .. workspace .. ", or send the window there",
    })
  end

  -- A bare modifier tap, on either side of the keyboard. One side is the
  -- command side: SHIFT flips SCOPE, ALT flips MODE and CTRL flips LIFETIME,
  -- the same things they flip in the chords outside the overlay, and SUPER --
  -- which is no axis, there being no fourth thing to flip -- rebuilds the
  -- overlay, as F5 does. The other side is the modifier side: a tap there switches
  -- that modifier in or out of what the next press holds down, so CTRL then
  -- the label is a Ctrl click. Which side is which is keyboard_modifier_side,
  -- and it is decided in imthemousenow-steer, not here -- this file reads no
  -- config, so every key says only which modifier it is and which side.
  --
  -- The modifier must appear in its OWN bind, as `SHIFT + Shift_L` rather than
  -- a bare `Shift_L`: at the moment Shift_L is released, SHIFT is still held,
  -- so a modmask of 0 matches nothing. This was measured, not assumed -- bare
  -- and mods-included binds were registered side by side and only the
  -- mods-included ones ever fired. It is the same shape as Hyprland's own
  -- `bindr = SUPER, SUPER_L` idiom.
  --
  -- `release` makes it a tap rather than a press, and `non_consuming` is what
  -- keeps the modifier working as a modifier -- without it `:` would be
  -- unreachable.
  local modifier_taps = {
    { "SHIFT", "Shift", "shift" },
    { "ALT", "Alt", "alt" },
    { "CTRL", "Control", "ctrl" },
    { "SUPER", "Super", "super" },
  }
  for _, tap in ipairs(modifier_taps) do
    local mask, keysym, name = tap[1], tap[2], tap[3]
    for _, side in ipairs({ { "L", "left" }, { "R", "right" } }) do
      hl.bind(mask .. " + " .. keysym .. "_" .. side[1],
        hl.dsp.exec_cmd("imthemousenow-steer modkey " .. name .. " " .. side[2]), {
        release = true,
        non_consuming = true,
        description = "Pointer: " .. side[2] .. " " .. name .. " -- a command, or held for the next press",
      })
    end
  end

  -- An overlay is measured once, when it opens: the window's geometry, and in
  -- hints mode the regions detected in one frame of the framebuffer. The
  -- screen does not hold still for that -- a page scrolls, a window resizes, a
  -- dialog opens -- and then the labels name things that have moved. F5 is
  -- the reload it looks like: the same overlay, measured again.
  -- Swapping two windows needs a second window named, and naming things on
  -- screen is what this tool already does -- so Tab opens a picker overlay
  -- rather than inventing a chord per direction. Window scope only: the swap
  -- starts from the window the overlay is drawn over.
  hl.bind("TAB", hl.dsp.exec_cmd("imthemousenow-steer swap"), {
    description = "Pointer: swap this window with one you pick",
  })

  hl.bind("F5", hl.dsp.exec_cmd("imthemousenow-steer refresh"), {
    description = "Pointer: rebuild the overlay against the screen as it is now",
  })

  -- Nothing here is printed on a key, and the overlay is invisible until one
  -- is pressed -- so the one thing a person cannot work out by looking is what
  -- they are allowed to press. F1 is where a help key lives, and pressing it
  -- again closes the sheet.
  --
  -- The sheet replaces the overlay for as long as it is up rather than sitting
  -- over it: it reads its own keyboard, and wl-kbptr is holding a grab. The
  -- overlay comes back unchanged when the sheet is dismissed -- see the `help`
  -- verb in bin/imthemousenow-steer.
  --
  -- `?` is deliberately NOT a second way in. On a QWERTY keyboard the keysym
  -- only exists because SHIFT is held, so `question` has to be bound as
  -- `SHIFT + question` -- a bare bind registers at modmask 0, never fires, and
  -- the `?` falls through to the window underneath and is typed into it. But
  -- `?` is not on SHIFT on every layout, so covering it properly means a pair
  -- of binds whose correctness depends on the keymap, and F1 already answers
  -- the question on every keymap there is. One key that always works beats two
  -- where one of them is a guess about the layout.
  hl.bind("F1", hl.dsp.exec_cmd("imthemousenow-steer help"), {
    description = "Pointer: show the keys this overlay listens to",
  })


  -- `-` `=` `_` `+` resize the window the overlay is drawn over -- the same
  -- four keys, the same directions and the same 100px step as SUPER + them
  -- outside the overlay, so nothing new is learned to use them here. They are
  -- keycodes rather than keysyms for the same reason Omarchy's own bindings
  -- are: code:20 and code:21 are that pair of keys on any keymap, whatever
  -- they print. Window scope only; imthemousenow-steer makes it a no-op over a
  -- monitor.
  hl.bind("code:20", hl.dsp.exec_cmd("imthemousenow-steer resize l"), {
    description = "Pointer: expand the window left",
  })
  hl.bind("code:21", hl.dsp.exec_cmd("imthemousenow-steer resize r"), {
    description = "Pointer: shrink the window left",
  })
  hl.bind("SHIFT + code:20", hl.dsp.exec_cmd("imthemousenow-steer resize u"), {
    description = "Pointer: shrink the window up",
  })
  hl.bind("SHIFT + code:21", hl.dsp.exec_cmd("imthemousenow-steer resize d"), {
    description = "Pointer: expand the window down",
  })

  hl.bind("LEFT", hl.dsp.exec_cmd("imthemousenow-steer arrow l"), {
    description = "Pointer: previous workspace, move the window left, or drop on the monitor left",
  })
  hl.bind("RIGHT", hl.dsp.exec_cmd("imthemousenow-steer arrow r"), {
    description = "Pointer: next workspace, move the window right, or drop on the monitor right",
  })
  hl.bind("UP", hl.dsp.exec_cmd("imthemousenow-steer arrow u"), {
    description = "Pointer: previous monitor, move the window up, or drop on the monitor above",
  })
  hl.bind("DOWN", hl.dsp.exec_cmd("imthemousenow-steer arrow d"), {
    description = "Pointer: next monitor, move the window down, or drop on the monitor below",
  })

end

hl.define_submap(SUBMAP_NAME, overlay_binds)

hl.define_submap(SUBMAP_POPUPS, function()
  overlay_binds()

  for _, name in ipairs(RELAY_KEYS) do
    imthemousenow_relay_bind(name)
  end

  -- Escape, the exception to the relay. See RELAY_KEYS.
  hl.bind("Escape", hl.dsp.exec_cmd("imthemousenow-steer escape"), {
    description = "Pointer: close the key sheet, or cancel the overlay",
  })

  -- Everything else. With no keyboard focus anywhere near the overlay, a key
  -- that is not bound here goes to the window underneath -- so a mistyped
  -- label would type into the page it is drawn over. Swallowing the rest
  -- makes the overlay as opaque to the keyboard as it looks.
  --
  -- "catchall" is the whole key string, not a modifier on one: Hyprland
  -- matches it with no modifiers held, and `CTRL + catchall` does not parse.
  -- So a plain key is swallowed and a chord is not -- CTRL + T still opens a
  -- tab in the browser underneath. Measured, not assumed.
  hl.bind("catchall", hl.dsp.exec_cmd("true"), {
    description = "Pointer: swallow keys the overlay does not use",
  })
end)

-- The keyboard of a hold. Every other submap here belongs to an overlay; this
-- one belongs to a button that is already down, with nothing drawn over the
-- screen -- which is the whole point of a hold, and also why it needs a submap
-- of its own rather than the overlay's. In the overlay's, `;` would switch an
-- ACTION that is already underway and a digit would change workspace with a
-- button held down on something.
--
-- Three ways to say the same four directions, because there is no one right
-- one: the arrows are what a hand reaches for without being told, hjkl is what
-- a vim hand reaches for, and WASD is what a hand already resting on the left
-- of the keyboard reaches for -- which is where a hand is when the other one is
-- not on a mouse. None of them cost anything: no key here has another meaning
-- to lose, since a hold reads the whole keyboard and nothing else is running.
--
-- `repeating` is what makes a held key move the pointer instead of nudging it
-- once, and SHIFT is the big step for crossing a screen you are not aiming
-- inside yet. Both steps are [imthemousenow.action.hold] in the config.
--
-- Space, Return and Escape all let go. Not one key, because there is nothing to
-- decide at that point -- the button comes up where the pointer is, whichever
-- of them you press -- and a hold is a state you want out of with whatever key
-- your hand finds first. Escape means "stop" everywhere else here, and letting
-- go IS stopping: there is no half-done hold to put back.
hl.define_submap(SUBMAP_HOLD, function()
  local directions = {
    l = { "LEFT", "h", "a" },
    r = { "RIGHT", "l", "d" },
    u = { "UP", "k", "w" },
    d = { "DOWN", "j", "s" },
  }
  local words = { l = "left", r = "right", u = "up", d = "down" }

  -- Every key under every set of held modifiers, not just bare. A hold can be
  -- pressing modifiers itself -- the ones toggled on in the overlay, held down
  -- with the button for the whole hold -- and the compositor sees what the
  -- virtual keyboard holds as held: with Super toggled on, `h` arrives as
  -- SUPER + h, matches nothing here, and the hold cannot be steered or let go.
  -- This file reads no config, so it cannot know which were toggled; it binds
  -- all sixteen sets instead. SHIFT still means the big step, which makes every
  -- step big in a hold that is holding Shift -- the one set where the two
  -- meanings cannot be told apart.
  local held = { "" }
  for _, mod in ipairs({ "CTRL", "ALT", "SUPER" }) do
    for i = 1, #held do
      held[#held + 1] = held[i] .. mod .. " + "
    end
  end

  for _, prefix in ipairs(held) do
    for direction, keys in pairs(directions) do
      for _, key in ipairs(keys) do
        hl.bind(prefix .. key, hl.dsp.exec_cmd("imthemousenow-hold move " .. direction), {
          repeating = true,
          description = "Pointer: drag " .. words[direction] .. " while the button is held",
        })
        hl.bind(prefix .. "SHIFT + " .. key, hl.dsp.exec_cmd("imthemousenow-hold move " .. direction .. " big"), {
          repeating = true,
          description = "Pointer: drag " .. words[direction] .. " in big steps",
        })
      end
    end

    for _, key in ipairs({ "space", "Return", "Escape" }) do
      for _, shift in ipairs({ "", "SHIFT + " }) do
        hl.bind(prefix .. shift .. key, hl.dsp.exec_cmd("imthemousenow-hold release"), {
          description = "Pointer: let go of the button and end the hold",
        })
      end
    end

    -- A real mouse button lets go too: a hand that has gone to the mouse has
    -- stopped steering by keyboard. Left, right, middle. The hold's own
    -- virtual press arrives here as well, just after the submap is entered,
    -- and `release mouse` is what knows to ignore that one. Non-consuming,
    -- because a bind on a button swallows it otherwise -- and the one it would
    -- swallow first is that virtual press, leaving a hold with nothing held.
    -- It also means the real click reaches what it was aimed at.
    for _, button in ipairs({ "mouse:272", "mouse:273", "mouse:274" }) do
      for _, shift in ipairs({ "", "SHIFT + " }) do
        hl.bind(prefix .. shift .. button, hl.dsp.exec_cmd("imthemousenow-hold release mouse"), {
          description = "Pointer: a mouse click ends the hold",
          non_consuming = true,
        })
      end
    end
  end

  -- Everything else, swallowed. A hold takes no keyboard focus -- there is no
  -- surface to take it with -- so a key with no binding here reaches the window
  -- the pointer is holding a button down on, and typing into the thing you are
  -- dragging is not something a mistyped key should be able to do. Same shape
  -- and same caveat as the popup-safe overlay's catchall: a plain key is
  -- swallowed, a chord is not.
  hl.bind("catchall", hl.dsp.exec_cmd("true"), {
    description = "Pointer: swallow keys a hold does not use",
  })
end)

-- The keyboard of a scroll. Like a hold's, it has nothing drawn over the
-- screen and needs a submap of its own; unlike a hold's, nothing is pressed,
-- and it stays on until Escape rather than until a button comes up.
--
-- The same three sets of directions as a hold: arrows, hjkl, WASD. Modifiers
-- are not toggled here: a hand scrolling reaches for Ctrl and holds it, and a
-- real modifier held while the wheel turns is what the page sees anyway. The
-- ones toggled on in the overlay before `/` stay held for the whole scroll.
hl.define_submap(SUBMAP_SCROLL, function()
  local directions = {
    left = { "LEFT", "h", "a" },
    right = { "RIGHT", "l", "d" },
    up = { "UP", "k", "w" },
    down = { "DOWN", "j", "s" },
  }

  -- Every set of held modifiers: the ones you hold with your own hand while
  -- scrolling, and the ones carried in from the overlay, which the scroll holds
  -- on a virtual keyboard and the compositor counts as held.
  local held = { "" }
  for _, mod in ipairs({ "CTRL", "ALT", "SHIFT", "SUPER" }) do
    for i = 1, #held do
      held[#held + 1] = held[i] .. mod .. " + "
    end
  end

  for _, prefix in ipairs(held) do
    for direction, keys in pairs(directions) do
      for _, key in ipairs(keys) do
        -- Not `repeating`: the wheel event cancels Hyprland's repeat, so the
        -- script repeats on its own until the key's release.
        hl.bind(prefix .. key, hl.dsp.exec_cmd("imthemousenow-scroll " .. direction), {
          description = "Pointer: scroll " .. direction,
        })
        hl.bind(prefix .. key, hl.dsp.exec_cmd("imthemousenow-scroll release"), {
          release = true,
          description = "Pointer: stop scrolling " .. direction,
        })
      end
    end
    hl.bind(prefix .. "Escape", hl.dsp.exec_cmd("imthemousenow-scroll stop"), {
      description = "Pointer: stop scrolling",
    })
  end

  hl.bind("catchall", hl.dsp.exec_cmd("true"), {
    description = "Pointer: swallow keys a scroll does not use",
  })
end)

-- Scroll where the pointer is, with no overlay. SUPER + ' sits next to
-- SUPER + ;, as `'` sits next to `;` inside the overlay.
o.bind("SUPER + APOSTROPHE", "Pointer: scroll where the pointer is", "imthemousenow-scroll begin")

-- The eight chords. A modifier does not name a value, it asks for the OTHER
-- value on its axis, and the axis starts from [imthemousenow.defaults] -- so
-- the bare chord is whatever the bar says SUPER + ; should be, and each
-- modifier still means exactly one thing on top of it.
--
-- The alternative was to read the defaults here and bake them into the eight
-- command strings. That works until the settings move somewhere a person can
-- change them: Hyprland reads this file when it loads, so every adjustment in
-- the bar would need a `hyprctl reload` before the keyboard agreed with the
-- panel. --flip is resolved by bin/imthemousenow on each press instead, which
-- costs nothing and is always current.
local chords = {
  -- modifiers                 flips                            label
  { "",                        "",                              "Pointer: the default chord" },
  { "SHIFT + ",                "--flip scope",                  "Pointer: the other scope" },
  { "ALT + ",                  "--flip mode",                   "Pointer: the other mode" },
  { "SHIFT + ALT + ",          "--flip scope --flip mode",      "Pointer: the other scope and mode" },
  { "CTRL + ",                 "--flip lifetime",               "Pointer: the other lifetime" },
  { "CTRL + SHIFT + ",         "--flip lifetime --flip scope",  "Pointer: the other lifetime and scope" },
  { "CTRL + ALT + ",           "--flip lifetime --flip mode",   "Pointer: the other lifetime and mode" },
  { "CTRL + SHIFT + ALT + ",   "--flip lifetime --flip scope --flip mode",
                                                                "Pointer: the other lifetime, scope and mode" },
}

for _, chord in ipairs(chords) do
  local modifiers, flips, label = table.unpack(chord)
  o.bind(
    "SUPER + " .. modifiers .. "SEMICOLON",
    label,
    "imthemousenow" .. (flips ~= "" and (" " .. flips) or "")
  )
end

-- Panic key. Ctrl+Alt+Delete is what people try when the screen stops
-- responding, so it doubles as the guaranteed way out of a stuck overlay:
-- Hyprland keybindings still fire while wl-kbptr holds the keyboard. This is
-- the global bind; the submap above needs its own copy, because a submap
-- shadows these.
-- imthemousenow-panic closes the overlay and then runs Omarchy's own action
-- for this key, so the default behaviour is preserved, not replaced.
hl.unbind("CTRL + ALT + DELETE")
o.bind("CTRL + ALT + DELETE", "Close all windows", "imthemousenow-panic")

-- And the same key inside each submap, because an active submap shadows the
-- global binds -- only its own fire, so without this the guaranteed way out of
-- a stuck overlay is the one thing an overlay takes away. It has to come after
-- the hl.unbind above: that removes the binding from every submap, this one
-- included, whatever order they were defined in. `hl.define_submap` appends to
-- a submap that already exists.
for _, submap in ipairs({ SUBMAP_NAME, SUBMAP_POPUPS, SUBMAP_HOLD, SUBMAP_SCROLL }) do
  hl.define_submap(submap, function()
    hl.bind("CTRL + ALT + DELETE", hl.dsp.exec_cmd("imthemousenow-panic"), {
      description = "Pointer: close the overlay and all windows",
    })
  end)
end
