# wl-kbptr colours, generated from the active Omarchy theme.
#
# Do not edit the rendered file (~/.local/state/omarchy/current/theme/wl-kbptr.conf)
# -- it is overwritten on every theme change. Edit the template instead:
#   ~/.config/omarchy/themed/wl-kbptr.conf.tpl
# Per-option overrides that survive re-theming go in:
#   ~/.config/omarchy/imthemousenow/config.local   (one `section.key=value` per line)
#
# Fonts are not set here; imthemousenow passes the current Omarchy font at
# launch. The trailing two hex digits on each colour are alpha.

[general]
# home_row_keys must be EXACTLY 11 characters or wl-kbptr refuses to start:
# the first 8 pick bisect sub-areas (4 columns x 2 rows, left to right, top row
# first), the last 3 are left, right and middle click. Left unset to keep
# upstream's built-in keys; override in ~/.config/omarchy/imthemousenow/config.local,
# e.g. general.home_row_keys=erui dfjk vbn  (without the spaces).
modes=tile,bisect
cancellation_status_code=1

[mode_tile]
label_color=#{{ foreground_strip }}ee
label_select_color=#{{ accent_strip }}ff
unselectable_bg_color=#{{ background_strip }}66
selectable_bg_color=#{{ background_strip }}33
selectable_border_color=#{{ accent_strip }}55
label_font_family=sans-serif
label_font_size=8 50% 100

[mode_floating]
# Floating labels land on top of whatever is on screen, so they cannot rely on
# alpha the way tile mode can: the label sits on a near-opaque chip of the
# theme background, making the text foreground-on-background, a pairing the
# theme already guarantees is readable. The screen behind is dimmed harder for
# the same reason.
source=stdin
label_color=#{{ bright_foreground_strip }}ff
label_select_color=#{{ yellow_strip }}ff
unselectable_bg_color=#{{ background_strip }}bb
selectable_bg_color=#{{ background_strip }}ee
selectable_border_color=#{{ accent_strip }}cc
label_font_family=sans-serif
label_font_size=12 50% 100

[mode_bisect]
label_color=#{{ foreground_strip }}ee
label_font_size=20
label_font_family=sans-serif
label_padding=12
pointer_size=20
pointer_color=#{{ red_strip }}dd
unselectable_bg_color=#{{ background_strip }}66
even_area_bg_color=#{{ green_strip }}33
even_area_border_color=#{{ green_strip }}88
odd_area_bg_color=#{{ blue_strip }}33
odd_area_border_color=#{{ blue_strip }}88
history_border_color=#{{ muted_strip }}99

[mode_split]
pointer_size=20
pointer_color=#{{ red_strip }}dd
bg_color=#{{ background_strip }}66
area_bg_color=#{{ background_strip }}88
vertical_color=#{{ blue_strip }}cc
horizontal_color=#{{ green_strip }}cc
history_border_color=#{{ muted_strip }}99

[mode_click]
button=left

# Not wl-kbptr's: imthemousenow strips this section before compiling, and uses
# it to tint the overlay when you switch ACTION mid-flight. It lives here
# because it is a palette value and must follow the theme.
#
# `red` rather than a hue chosen by eye: Omarchy themes collapse semantic
# colour names freely (in Matte Black, blue == accent and yellow is a red), but
# accent and red were distinct in every theme checked, and they are the pair
# that reads as "normal" versus "careful".
# left-click is the untinted overlay, so it has no tint to reuse -- but the OSD
# still has to draw its word in something, and accent is what "this is the
# normal thing" already looks like everywhere else in this overlay.
[imthemousenow.action.left-click]
color=#{{ accent_strip }}

[imthemousenow.action.right-click]
color=#{{ red_strip }}

# `magenta` for move, by the same survey that picked red. Across all 22 shipped
# themes it is the hue that least often collapses into accent (the untinted
# overlay) or red (the right-click tint): 4 themes where it reads close to one
# of them, against 7 for cyan, 8 for yellow and 9 for green. It is also the
# right meaning -- move clicks nothing, so it should not borrow red's "careful"
# or the accent's "this is the normal thing".
[imthemousenow.action.move]
color=#{{ magenta_strip }}

# `yellow` for drag, by the same survey that picked red and magenta, rerun with
# the two of them plus accent as the taken set. Of the hues present in all 22
# shipped themes, yellow collides with one of those three least often (9
# themes, against 11 for green, 12 for cyan and 22 for blue -- blue IS accent
# almost everywhere). `brown` scores better still, at 6, but four themes do not
# define it at all, and a colour that renders as an empty string is a broken
# config line rather than a dim tint.
#
# Both passes of a drag are the same colour, and that is a decision rather than
# an omission. A second hue would have to be distinct from accent, red, magenta
# AND this one, and nothing left clears that bar: the best remaining pair still
# reads alike in 5 of the 22 themes, which is a tint that lies about which half
# of the drag you are in. The word does that job instead -- DRAG, then DROP --
# which is what the OSD is for.
[imthemousenow.action.drag]
color=#{{ yellow_strip }}

[imthemousenow.action.drop]
color=#{{ yellow_strip }}
