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
-- The same reasoning gives a monitor-scope overlay its own navigation. When
-- the overlay covers a whole monitor, the thing you want to aim at is often
-- on another workspace or another screen, and leaving the overlay to go there
-- costs you the overlay. These keys move the view underneath it instead and
-- the overlay is rebuilt where you land. wl-kbptr labels never use digits or
-- arrows, so nothing is taken away from it. In window scope the commands
-- return without doing anything: the overlay is tied to one window there.
hl.define_submap(SUBMAP_NAME, function()
  hl.bind("SEMICOLON", hl.dsp.exec_cmd("imthemousenow-steer action right-click"), {
    description = "Pointer: switch to a right click",
  })
  -- `:` is the same key with SHIFT, which keeps the two ACTION switches on one
  -- physical key: `;` to click differently, `:` to not click at all.
  hl.bind("SHIFT + SEMICOLON", hl.dsp.exec_cmd("imthemousenow-steer action move"), {
    description = "Pointer: switch to move without clicking",
  })

  for workspace = 1, 9 do
    hl.bind(tostring(workspace), hl.dsp.exec_cmd("imthemousenow-steer workspace " .. workspace), {
      description = "Pointer: move the overlay to workspace " .. workspace,
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

  hl.bind("LEFT", hl.dsp.exec_cmd("imthemousenow-steer workspace -1"), {
    description = "Pointer: move the overlay to the previous workspace",
  })
  hl.bind("RIGHT", hl.dsp.exec_cmd("imthemousenow-steer workspace +1"), {
    description = "Pointer: move the overlay to the next workspace",
  })
  hl.bind("UP", hl.dsp.exec_cmd("imthemousenow-steer monitor -1"), {
    description = "Pointer: move the overlay to the previous monitor",
  })
  hl.bind("DOWN", hl.dsp.exec_cmd("imthemousenow-steer monitor +1"), {
    description = "Pointer: move the overlay to the next monitor",
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
-- Hyprland keybindings still fire while wl-kbptr holds the keyboard.
-- imthemousenow-panic closes the overlay and then runs Omarchy's own action
-- for this key, so the default behaviour is preserved, not replaced.
hl.unbind("CTRL + ALT + DELETE")
o.bind("CTRL + ALT + DELETE", "Close all windows", "imthemousenow-panic")
