# Lessons learned

Notes for whoever works on this next — human or agent. `design-notes.md` records
*what* was decided; this records *what it cost to find out*, so you do not pay
twice.

## Verify against the running system, not against your model of it

Every serious mistake in this project came from reasoning confidently about a
thing that was cheap to check.

- **`home_row_keys` must be exactly 11 characters.** Nine was shipped. wl-kbptr
  rejects the *entire config file* on a bad value, so every mode exited before
  drawing and `SUPER + ;` looked like a dead keybinding. Flag construction had
  been tested; the binary had never been run against the generated config.
- **The config compiler blanked the whole palette.** The ini parser stripped
  `#` as an inline comment, but every colour value *starts* with `#`. Caught
  only because the compiled output was read back afterwards.
- **wl-kbptr already had the feature.** Two rounds of design went into
  per-selection right-click before reading `main.c`, which derives `a s d f
  j k l m` + `g`/`h`/`b` from the keymap when `home_row_keys` is empty. The
  answer was in `/usr/src/debug/wl-kbptr-omarchy/` the whole time, because the
  package is built with debug sources. **Read it before designing.**

A cheap and effective test for "does wl-kbptr accept this config": launch it
under `timeout 2`. A config error exits instantly; exit code 124 means it
survived, which means the config parsed. Always pair it with a deliberately
broken control (a 9-character `home_row_keys`) to prove the test discriminates —
a test that passes for the wrong reason is worse than none.

## wl-kbptr facts worth not rediscovering

- Modes chain: `tile`, `bisect`, `split`, `floating`, `click`. `click` takes
  **no keys at all** — it clicks the instant it is entered. Any per-selection
  key behaviour has to live in `bisect` or `split`.
- `bisect` and `split` both map the last three `home_row_keys` to left/right/
  middle click: they set the button and commit immediately. That is a genuine
  one-off click, but there is no persistent state, so nothing can *display*
  which button is armed.
- Tile mode caps the grid at 26×26 cells but derives rows and columns by
  truncating two independent square roots, so the product can **overshoot the
  cap** — 680 cells in a 1330×1102 window. Label length is "how many times does
  the cell count divide by the symbol count", so one cell past 675 adds a third
  character to every label. Fix: a 27th label symbol raises the ceiling to 729.
- The CLI flag is `--only-print`, not `--print-only` (the original spec was
  wrong).
- `cancellation_status_code` defaults to 0, which makes Escape
  indistinguishable from a completed click. We set it to 1; continuous lifetime
  depends on it.

- **Picking a theme-following accent: survey, do not eyeball.** Omarchy themes
  collapse semantic colour names freely, so a hue that reads as distinct in one
  theme is the accent in another. Parse every `/usr/share/omarchy/themes/*/
  colors.toml` and count the themes where a candidate lands on, or within ~15
  degrees of hue of, the colours already in use. For the ACTION tints the count
  of problem themes was: magenta 4, cyan 7, yellow 8, green 9 -- which is why
  right-click is `red` and move is `magenta`. `vantablack` and `white` are
  monochrome and no choice helps there. `{{ <key>_strip }}` works for any key
  in `colors.toml`, not just the ones existing templates happen to use.

## Omarchy / Hyprland facts

- **Omarchy's Hyprland config uses the Lua parser**, and this changes the tools
  available:
  - `hyprctl keyword` does not work at all — *"keyword can't work with
    non-legacy parsers."* Runtime binds cannot be added that way.
  - `hyprctl eval '<lua>'` executes against the live config state, with `hl`
    and `o` in scope. It returns only `ok`, so to read anything back, write to
    a file from Lua and read the file.
  - Dispatch is `hyprctl dispatch 'hl.dsp.submap("name")'`. The bare
    `hyprctl dispatch submap name` form fails to parse. This applies to EVERY
    dispatcher, not just submap: `hyprctl dispatch workspace 5` is a parse
    error, not a workspace switch.
  - A dispatch Hyprland could not parse prints `error: ...` and **still exits
    0**, so `|| true` on a dispatch hides the failure completely. Test the
    output for an `error:` prefix, not the exit status.
  - The dispatcher set is curated and does not match Hyprland's own names.
    `hl.dsp.workspace` is a *table* (`change_id`, `move`, `rename`,
    `swap_monitors`, `toggle_special`), not the workspace switcher. Switching
    is `hl.dsp.focus`, which takes `direction`, `monitor`, `win` or
    `workspace`; `monitor` and `workspace` each accept an absolute name/id or
    a signed relative step, so `{workspace="5"}`, `{workspace="+1"}` and
    `{monitor="-1"}` are all it takes. Passing a wrong key is the fastest way
    to enumerate the accepted ones -- the error lists them.
  - To discover the API, dump it from `hyprctl eval` into a file
    (`for k in pairs(hl.dsp) do ... end`, write with `io.open`), since eval
    itself only ever returns `ok`.
  - Key names are keysyms: `SEMICOLON`, not `;`, which is rejected.
  - The dispatcher is `hl.dsp.exec_cmd`, not `hl.dsp.exec`.
- **Arrow-key submap binds do not survive an overlay.** When wl-kbptr exits,
  Hyprland silently drops exactly the `LEFT`/`RIGHT`/`UP`/`DOWN` binds of our
  submap; `SEMICOLON` and the nine digit binds beside them are untouched. It
  reproduces with wl-kbptr launched by hand, no submap entered and no wrapper
  involved, so it is the client's keyboard grab going away, not anything this
  plugin does. Entering and resetting the submap by hand never drops them, and
  registration order makes no difference. The workaround is
  `ensure_arrow_binds` in the wrapper: re-assert them before every launch.
  - `hl.define_submap` on an existing submap **appends** to it, so a partial
    body is the right way to re-add a few binds.
  - A bind re-asserted while it is still present is **duplicated**, not
    replaced, and duplicates accumulate. Always diff against
    `hyprctl -j binds` and send only what is missing.
- **A bare modifier tap is bindable, but the modifier must be in its own
  modmask**: `hl.bind("SHIFT + Shift_L", ..., { release = true, non_consuming =
  true })`. A bare `hl.bind("Shift_L", ...)` registers fine, shows up in
  `hyprctl binds` with `modmask=0`, and never fires -- at the moment Shift_L is
  released SHIFT is still held, so nothing matches. Same shape as Hyprland's
  own `bindr = SUPER, SUPER_L`. `release` is what makes it a tap; there is no
  `hl.bindr`. `non_consuming` is not optional -- without it SHIFT stops working
  as a modifier while the submap is active and `:` becomes unreachable. Bind
  both `_L` and `_R`. Unlike the arrows, these survive an overlay exit.
  - **To settle a question like that, bind every candidate at once.** Register
    the variants side by side as log-only probes writing distinct lines to one
    file, have a human tap the key once, and read which line appears. One
    keypress answers what any amount of bind-syntax guessing will not.
  - Hyprland does **not** feed synthesised keys (`hl.dsp.send_key_state`) back
    through the bind system, so a tap bind cannot be tested from a script. Only
    a human pressing the key proves it fires.
  - A modifier release is also how a chord ends, so a release bind fires on the
    tail of one -- `:` is SHIFT + SEMICOLON, and its SHIFT release reaches the
    tap bind. Two guards, because a time window alone is not enough: stamp
    every other bind and ignore a tap within `switch.tap_debounce_ms`, AND
    ignore a tap while a relaunch is still pending, which covers a SHIFT held
    longer than the window. Have the modifier binds *not* stamp, or two taps in
    a row debounce each other.
- **Hyprland keybindings still fire while wl-kbptr holds the keyboard grab.**
  This is the cause of the old double-instance lockout, and also what makes
  both the panic key and the `;` submap possible at all.
- **A submap is the right tool for a key that should exist only sometimes.** It
  rebinds one key for a bounded lifetime and lets every other key through to
  the grabbing client. Always reset it from a trap — a submap left active makes
  its key dead system-wide.
- **Theme templates only render during an actual theme set.**
  `omarchy-theme-set-templates` writes into `.../current/next-theme` and
  **skips any output file that already exists**, so calling it directly after
  editing a template appears to do nothing. Re-apply the theme
  (`omarchy-theme-set <name>`) to flush it. This cost a confusing detour when a
  template edit "didn't take" — the repo file was right and the rendered file
  was stale.
- **Semantic colour names collapse.** In Matte Black, `blue == accent`,
  `cyan == foreground`, `yellow` is a red, `green` is amber, and
  `red == magenta == purple`. Never assume two hue names differ. `background`
  vs `foreground` and `accent` are the reliable ones; `accent` vs `red` held
  distinct in every theme checked and is the pair used for left vs right click.
- Omarchy's plugin installer **never runs plugin code, install hooks, or sudo**,
  which is why `install.sh` is shipped separately and there is no
  `manifest.json` until there is a real shell surface to register.

## Design decisions that are load-bearing

- **Four orthogonal axes, not named presets.** MODE / SCOPE / ACTION / LIFETIME.
  Presets grew one entry per combination and the names said nothing about how
  they related. Eight chords are one key plus three modifiers that each flip one
  axis. If you add an axis, do not add a modifier — the chord space is full.
- **ACTION is chosen inside the overlay**, because it is the one axis you cannot
  sensibly decide before seeing the target. `;` tears the overlay down and
  relaunches it tinted. The flicker and the discarded typed prefix were
  explicitly accepted by the user, twice, after being offered cheaper
  alternatives, and confirmed tolerable in real use afterwards. Do not "fix"
  this by moving ACTION back to a chord. A flicker-free version needs
  imthemousenow to own the overlay rather than drive wl-kbptr — worth doing
  eventually, but it is finessing, and functionality comes first.
- **Hints click directly** (`floating,click`, no refine). A hint already names a
  target; asking the user to then aim at it was the thing they rejected. Grid
  keeps `bisect`, which is the entire point of a grid.
- **`home_row_keys` is deliberately unset**, so wl-kbptr derives it from the
  active keymap instead of assuming QWERTY.
- **One overlay at a time, enforced by a non-blocking `flock`** held by the
  wrapper for its lifetime, so the kernel releases it however the process dies.
  Two stacked overlays lock the session out — this is a safety property, not a
  nicety.
- **The config is a superset of wl-kbptr's**, passing unknown sections through
  verbatim. Options upstream adds tomorrow work today. Only `[imthemousenow]`
  and `[mode.*]` are reserved, and the reserved test must handle both TOML's
  nesting and the theme template's flat ini spelling of the same section.

## Working style that paid off

- The user is exacting, technically fluent, and *invites* being challenged —
  they explicitly asked for their naming taxonomy to be challenged and changed
  it in response. Push back with reasoning when there is a real problem; they
  will also overrule you, and when they do (the flicker), build what they asked
  for without relitigating.
- State the cost of a trade-off plainly *before* implementing, not in a footnote
  afterwards. Right-click silently vanished from hints in one change because the
  consequence was buried in a commit message instead of raised as a question.
- Report what was actually verified and what was not. "Tested" should mean a
  command ran and its output was read.
