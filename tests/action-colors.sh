#!/bin/bash
# Can you tell the six ACTION colours apart, in every theme Omarchy ships?
#
# Four of them are derived from the fifth by turning an OkLCh wheel, and the
# whole point of deriving them is that nobody checks them by eye afterwards.
# The two guard rails in `derive_action_colors` exist because two classes of
# theme break the naive version -- a near-grey accent (rotating the hue of a
# grey gives five greys) and a very light one (sRGB has no chroma left up there)
# -- and both classes are shipped, so both are asserted here against the real
# palettes rather than against a fixture.
#
# Separation is measured in Oklab, where the distance from black to white is
# 1.0. 0.09 is the floor: comfortably visible, and below what any shipped theme
# manages today, so this fails on a regression rather than on a rounding change.
#
#   ./tests/action-colors.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THEMES="${OMARCHY_THEMES:-/usr/share/omarchy/themes}"

# A home of this test's own, for the reason the other tests have one: a colour
# pinned by hand in the tester's config.toml is a decision the config tool is
# required to leave alone, so it would quietly replace one of the five derived
# colours being measured here and the separation asserted below would be of a
# set nobody ships.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

HOME="$WORK" MOUSENOW_PLUGIN_DIR="$REPO" python3 - "$REPO" "$THEMES" <<'PY'
import glob, importlib.machinery, importlib.util, math, os, re, sys

repo, themes_dir = sys.argv[1], sys.argv[2]

# The config tool is the implementation under test; load it as a module rather
# than reimplementing any of its arithmetic here.
# No .py extension, so the loader has to be named rather than inferred.
loader = importlib.machinery.SourceFileLoader("cfg", os.path.join(repo, "bin", "imthemousenow-config"))
spec = importlib.util.spec_from_loader("cfg", loader)
cfg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cfg)

MIN_SEPARATION = 0.09
failures = 0

# The five on the wheel plus drop, which is not on it: drop wears drag's hue a
# step lighter, so the pair it could collide with is drag, and nothing else here
# would notice if it did.
ACTIONS = list(cfg.WHEEL) + ["drop"]


def oklab(hex_color):
    light, chroma, hue = cfg.to_oklch(cfg.parse_hex(hex_color))
    return (light, chroma * math.cos(math.radians(hue)), chroma * math.sin(math.radians(hue)))


def separation(a, b):
    return math.dist(oklab(a), oklab(b))


def palette(accent):
    """What the real derivation makes of one accent."""
    merged = {"imthemousenow": {"action": {"left-click": {"color": accent}}}}
    cfg.derive_action_colors(merged)
    actions = merged["imthemousenow"]["action"]
    return [actions[name]["color"] for name in ACTIONS]


accents = {}
for path in sorted(glob.glob(os.path.join(themes_dir, "*", "colors.toml"))):
    name = path.split(os.sep)[-2]
    for line in open(path):
        found = re.match(r'\s*accent\s*=\s*"(#[0-9a-fA-F]{6})"', line)
        if found:
            accents[name] = found.group(1)

if not accents:
    print(f"SKIP  no themes found under {themes_dir}")
    raise SystemExit(0)

worst = (9.0, "")
for name, accent in sorted(accents.items()):
    colors = palette(accent)
    if len(set(c.lower() for c in colors)) != len(ACTIONS):
        print(f"FAIL  {name}: two ACTIONs got the same colour -- {colors}")
        failures += 1
        continue
    pairs = [
        (separation(colors[i], colors[j]), ACTIONS[i], ACTIONS[j])
        for i in range(len(colors))
        for j in range(i + 1, len(colors))
    ]
    closest = min(pairs)
    if closest[0] < worst[0]:
        worst = (closest[0], name)
    if closest[0] < MIN_SEPARATION:
        print(f"FAIL  {name}: {closest[1]} and {closest[2]} differ by only {closest[0]:.3f}")
        failures += 1

if not failures:
    print(f"ok    all {len(accents)} themes separate six ACTIONs (closest: {worst[1]} at {worst[0]:.3f})")

# left-click is the accent itself, untouched. It is the one colour the theme
# actually chose, and a tool that "improved" it would be repainting the desktop.
for name, accent in sorted(accents.items()):
    if palette(accent)[0].lower() != accent.lower():
        print(f"FAIL  {name}: left-click is {palette(accent)[0]}, not the accent {accent}")
        failures += 1
        break
else:
    print("ok    left-click is the theme's accent, exactly")

# A colour set by hand is a decision; only the gaps are filled.
merged = {"imthemousenow": {"action": {
    "left-click": {"color": "#e68e0d"},
    "drag": {"color": "#123456"},
}}}
cfg.derive_action_colors(merged)
actions = merged["imthemousenow"]["action"]
if actions["drag"]["color"] != "#123456":
    print(f"FAIL  an explicit colour was overwritten with {actions['drag']['color']}")
    failures += 1
elif not cfg.parse_hex(actions["drop"]["color"]):
    print("FAIL  the remaining ACTIONs were not derived")
    failures += 1
else:
    print("ok    an explicit colour wins, and the rest are still derived")

# No accent at all (theme_colors off, nothing written by hand): every tint stays
# unset, which is what the callers read as "do not tint".
merged = {"imthemousenow": {"action": {"move": {"label": "move"}}}}
cfg.derive_action_colors(merged)
if any("color" in body for body in merged["imthemousenow"]["action"].values()):
    print("FAIL  colours were invented with no accent to derive them from")
    failures += 1
else:
    print("ok    no accent means no tint, rather than a guess")

print()
if failures:
    print(f"{failures} failing")
    raise SystemExit(1)
print("all checks passed")
PY
