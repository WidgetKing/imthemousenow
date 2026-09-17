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
-- They compose, so you never memorise eight bindings: you memorise one, plus
-- what each modifier means. ACTION is not on a modifier because it is decided
-- after you can see the overlay, not before: `;` switches it.

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
hl.define_submap(SUBMAP_NAME, function()
  hl.bind("SEMICOLON", hl.dsp.exec_cmd("imthemousenow --switch-action"), {
    description = "Pointer: switch between left and right click",
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
