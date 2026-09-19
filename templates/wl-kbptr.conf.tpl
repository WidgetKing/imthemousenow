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
# ONE colour, and the other four ACTIONs are turned off it by
# `derive_action_colors` in bin/imthemousenow-config -- 72 degrees apart around
# an OkLCh wheel, which is a wheel an eye divides evenly. The reasoning, and the
# measurements across all 22 shipped themes that set its two guard rails, are
# there rather than here.
#
# The accent, because the ordinary overlay should look like the rest of the
# desktop rather than announcing itself: left-click is what a pointer does when
# you have not said otherwise. It is also the seed for everything else, so a
# theme gets a whole ACTION palette by having an accent, and overriding this one
# line in ~/.config/omarchy/themed/wl-kbptr.conf.tpl repaints all five.
#
# To pin one ACTION's colour instead, name it in
# ~/.config/omarchy/imthemousenow/config.toml -- anything written by hand is
# left alone, and only the missing ones are derived.
[imthemousenow.action.left-click]
color=#{{ accent_strip }}
