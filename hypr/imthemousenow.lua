-- imthemousenow: keyboard-driven pointer control.
--
-- Loaded from ~/.config/hypr/hyprland.lua via:
--   require("omarchy.plugins.imthemousenow.hypr.imthemousenow")
-- install.sh adds that line, guarded by a marker comment.
--
-- Override any of these in ~/.config/hypr/bindings.lua by calling
-- hl.unbind("SUPER + SEMICOLON") first, then binding it yourself.

-- The overlay is a layer-shell surface that must appear instantly: a fade or
-- slide makes the labels unreadable for the first frames.
hl.layer_rule({ match = { namespace = "wl-kbptr" }, no_anim = true, animation = "none" })

o.bind("SUPER + SEMICOLON", "Pointer: grid", "imthemousenow quick")
o.bind("SUPER + SHIFT + SEMICOLON", "Pointer: detect targets", "imthemousenow detect")
o.bind("SUPER + ALT + SEMICOLON", "Pointer: pick window", "imthemousenow windows")
o.bind("SUPER + CTRL + SEMICOLON", "Pointer: precise split", "imthemousenow precise")

-- Stays up after each click and reopens, until Escape. For bursts of clicking.
o.bind(
  "SUPER + CTRL + SHIFT + SEMICOLON",
  "Pointer: repeat clicking",
  "imthemousenow quick --repeat"
)

-- Detect, confined to the focused window.
o.bind(
  "SUPER + SHIFT + ALT + SEMICOLON",
  "Pointer: detect in window",
  "imthemousenow detect --scope active-window"
)

-- Panic key. Ctrl+Alt+Delete is what people try when the screen stops
-- responding, so it doubles as the guaranteed way out of a stuck overlay:
-- Hyprland keybindings still fire while wl-kbptr holds the keyboard.
-- imthemousenow-panic closes the overlay and then runs Omarchy's own action
-- for this key, so the default behaviour is preserved, not replaced.
hl.unbind("CTRL + ALT + DELETE")
o.bind("CTRL + ALT + DELETE", "Close all windows", "imthemousenow-panic")
