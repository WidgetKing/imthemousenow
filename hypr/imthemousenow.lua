-- imthemousenow: keyboard-driven pointer control.
--
-- Loaded from ~/.config/hypr/hyprland.lua via:
--   require("omarchy.plugins.imthemousenow.hypr.imthemousenow")
-- install.sh adds that line, guarded by a marker comment, when the full
-- keybindings choice is picked (--keybinds full, the default).
--
-- This file is only the two entry points -- SUPER + ' and the eight
-- SUPER + ; chords -- plus the require below that pulls in everything the
-- overlay itself needs. It carries no overlay logic of its own: that is
-- hypr/imthemousenow-submap.lua, which install.sh can also wire up on its
-- own (--keybinds submap) for a setup that wants its own entry hotkey. See
-- that file's header for what the three --keybinds choices give you, and
-- docs/manual/02-keybindings.md, "Bring your own keybinding", for how to
-- point your own bind at it.
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
-- They compose, so you never memorise eight bindings: you memorise one, plus
-- what each modifier means. ACTION is not on a modifier because it is decided
-- after you can see the overlay, not before -- see overlay_binds() in
-- hypr/imthemousenow-submap.lua.
require("omarchy.plugins.imthemousenow.hypr.imthemousenow-submap")

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
