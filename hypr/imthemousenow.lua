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
--   SHIFT  flips SCOPE     window -> monitor
--   ALT    flips MODE      hints  -> grid
--   CTRL   flips LIFETIME  single -> continuous
--
-- SHIFT and ALT keep those meanings inside the overlay: tapped on their own,
-- they flip the same axis again, so the overlay you are looking at can become
-- the one you meant without closing it.
--
-- They compose, so you never memorise eight bindings: you memorise one, plus
-- what each modifier means. ACTION is not on a modifier because it is decided
-- after you can see the overlay, not before: `;` and `:` switch it.

-- The overlay is a layer-shell surface that must appear instantly: a fade or
-- slide makes the labels unreadable for the first frames.
hl.layer_rule({ match = { namespace = "wl-kbptr" }, no_anim = true, animation = "none" })

-- Must match SUBMAP in bin/imthemousenow.
SUBMAP_NAME = "imthemousenow"

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
hl.define_submap(SUBMAP_NAME, function()
  hl.bind("SEMICOLON", hl.dsp.exec_cmd("imthemousenow-steer action right-click"), {
    description = "Pointer: switch to a right click",
  })
  -- `:` is the same key with SHIFT, which keeps the two ACTION switches on one
  -- physical key: `;` to click differently, `:` to not click at all.
  hl.bind("SHIFT + SEMICOLON", hl.dsp.exec_cmd("imthemousenow-steer action move"), {
    description = "Pointer: switch to move without clicking",
  })

  -- The digits and the arrows are read by SCOPE, not fixed to one dispatcher:
  -- see the `arrow`/`digit` verbs in imthemousenow-steer. Over a whole monitor
  -- they move the view under the overlay; over a window they move that window,
  -- which is what SUPER + an arrow and SUPER + SHIFT + a digit do outside the
  -- overlay. Both keep you aiming at the thing you opened the overlay for.
  for workspace = 1, 9 do
    hl.bind(tostring(workspace), hl.dsp.exec_cmd("imthemousenow-steer digit " .. workspace), {
      description = "Pointer: go to workspace " .. workspace .. ", or send the window there",
    })
  end

  -- A bare SHIFT or ALT tap flips the axis its chord modifier flips, which is
  -- the same thing it means outside the overlay: SHIFT is SCOPE, ALT is MODE.
  --
  -- The modifier must appear in its OWN bind, as `SHIFT + Shift_L` rather than
  -- a bare `Shift_L`: at the moment Shift_L is released, SHIFT is still held,
  -- so a modmask of 0 matches nothing. This was measured, not assumed -- bare
  -- and mods-included binds were registered side by side and only the
  -- mods-included ones ever fired. It is the same shape as Hyprland's own
  -- `bindr = SUPER, SUPER_L` idiom.
  --
  -- `release` makes it a tap rather than a press, and `non_consuming` is what
  -- keeps SHIFT working as a modifier -- without it `:` would be unreachable.
  -- Both sides of the keyboard, because neither is the "real" one.
  for _, key in ipairs({ "Shift_L", "Shift_R" }) do
    hl.bind("SHIFT + " .. key, hl.dsp.exec_cmd("imthemousenow-steer scope"), {
      release = true,
      non_consuming = true,
      description = "Pointer: switch between window and monitor scope",
    })
  end
  for _, key in ipairs({ "Alt_L", "Alt_R" }) do
    hl.bind("ALT + " .. key, hl.dsp.exec_cmd("imthemousenow-steer mode"), {
      release = true,
      non_consuming = true,
      description = "Pointer: switch between hints and grid",
    })
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

  hl.bind("LEFT", hl.dsp.exec_cmd("imthemousenow-steer arrow l"), {
    description = "Pointer: previous workspace, or move the window left",
  })
  hl.bind("RIGHT", hl.dsp.exec_cmd("imthemousenow-steer arrow r"), {
    description = "Pointer: next workspace, or move the window right",
  })
  hl.bind("UP", hl.dsp.exec_cmd("imthemousenow-steer arrow u"), {
    description = "Pointer: previous monitor, or move the window up",
  })
  hl.bind("DOWN", hl.dsp.exec_cmd("imthemousenow-steer arrow d"), {
    description = "Pointer: next monitor, or move the window down",
  })

end)

local chords = {
  -- modifiers                      scope       mode     lifetime      label
  { "",                             "window",  "hints", "single",     "Pointer: hints" },
  { "SHIFT + ",                     "monitor", "hints", "single",     "Pointer: hints on monitor" },
  { "ALT + ",                       "window",  "grid",  "single",     "Pointer: grid" },
  { "SHIFT + ALT + ",               "monitor", "grid",  "single",     "Pointer: grid on monitor" },
  { "CTRL + ",                      "window",  "hints", "continuous", "Pointer: hints, keep going" },
  { "CTRL + SHIFT + ",              "monitor", "hints", "continuous", "Pointer: hints on monitor, keep going" },
  { "CTRL + ALT + ",                "window",  "grid",  "continuous", "Pointer: grid, keep going" },
  { "CTRL + SHIFT + ALT + ",        "monitor", "grid",  "continuous", "Pointer: grid on monitor, keep going" },
}

for _, chord in ipairs(chords) do
  local modifiers, scope, mode, lifetime, label = table.unpack(chord)
  o.bind(
    "SUPER + " .. modifiers .. "SEMICOLON",
    label,
    ("imthemousenow --mode %s --scope %s --lifetime %s"):format(mode, scope, lifetime)
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

-- And the same key inside the submap, because an active submap shadows the
-- global binds -- only its own fire, so without this the guaranteed way out of
-- a stuck overlay is the one thing an overlay takes away. It has to come after
-- the hl.unbind above: that removes the binding from every submap, this one
-- included, whatever order they were defined in. `hl.define_submap` appends to
-- a submap that already exists.
hl.define_submap(SUBMAP_NAME, function()
  hl.bind("CTRL + ALT + DELETE", hl.dsp.exec_cmd("imthemousenow-panic"), {
    description = "Pointer: close the overlay and all windows",
  })
end)
