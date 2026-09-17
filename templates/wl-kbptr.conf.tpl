# wl-kbptr colours, generated from the active Omarchy theme.
#
# Do not edit the rendered file (~/.local/state/omarchy/current/theme/wl-kbptr.conf)
# -- it is overwritten on every theme change. Edit the template instead:
#   ~/.config/omarchy/themed/wl-kbptr.conf.tpl
# Per-option overrides that survive re-theming go in:
#   ~/.config/omarchy/kbptr/config.local   (one `section.key=value` per line)
#
# Fonts are not set here; omarchy-kbptr passes the current Omarchy font at
# launch. The trailing two hex digits on each colour are alpha.

[general]
# home_row_keys must be EXACTLY 11 characters or wl-kbptr refuses to start:
# the first 8 pick bisect sub-areas (4 columns x 2 rows, left to right, top row
# first), the last 3 are left, right and middle click. Left unset to keep
# upstream's built-in keys; override in ~/.config/omarchy/kbptr/config.local,
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
label_symbols=abcdefghijklmnopqrstuvwxyz

[mode_floating]
source=stdin
label_color=#{{ foreground_strip }}ee
label_select_color=#{{ accent_strip }}ff
unselectable_bg_color=#{{ background_strip }}66
selectable_bg_color=#{{ accent_strip }}22
selectable_border_color=#{{ accent_strip }}88
label_font_family=sans-serif
label_font_size=12 50% 100
label_symbols=abcdefghijklmnopqrstuvwxyz

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
