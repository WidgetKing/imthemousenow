-- omarchy-kbptr: keyboard-driven pointer control.
--
-- Loaded from ~/.config/hypr/hyprland.lua via:
--   require("omarchy.plugins.kbptr.hypr.kbptr")
-- install.sh adds that line, guarded by a marker comment.
--
-- Override any of these in ~/.config/hypr/bindings.lua by calling
-- hl.unbind("SUPER + SEMICOLON") first, then binding it yourself.

-- The overlay is a layer-shell surface that must appear instantly: a fade or
-- slide makes the labels unreadable for the first frames.
hl.layer_rule({ match = { namespace = "wl-kbptr" }, no_anim = true, animation = "none" })

o.bind("SUPER + SEMICOLON", "Pointer: grid", "omarchy-kbptr quick")
o.bind("SUPER + SHIFT + SEMICOLON", "Pointer: detect targets", "omarchy-kbptr detect")
o.bind("SUPER + ALT + SEMICOLON", "Pointer: pick window", "omarchy-kbptr windows")
o.bind("SUPER + CTRL + SEMICOLON", "Pointer: precise split", "omarchy-kbptr precise")
