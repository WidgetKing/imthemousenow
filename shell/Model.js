// Reading and shaping imthemousenow's config for the panel.
//
// The panel never parses config.toml. It asks `imthemousenow-config env` --
// one subprocess, every merged setting, already validated -- and writes back
// through `set` / `toggle`, which validate against the same vocabulary
// `check` uses. That keeps exactly one program able to interpret the config,
// which is what stopped the old menu rows from drifting out of step with it.

.pragma library

// `MOUSENOW_CFG_OSD_ON_START=false` -> settings["osd.on_start"] = "false".
// The names are lossy: `on_start` and `on-start` both upper-case to the same
// variable, and `left-click` arrives as LEFT_CLICK. That does not matter for
// the keys below, which are looked up by the same transform that produced
// them, never by reversing it.
function parseEnv(text) {
  var out = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line || line.indexOf("MOUSENOW_CFG_") !== 0) continue
    var eq = line.indexOf("=")
    if (eq < 0) continue
    out[line.slice(0, eq)] = unquote(line.slice(eq + 1))
  }
  return out
}

// shlex.quote() output: bare, or single-quoted with '"'"' for an embedded quote.
function unquote(value) {
  var text = String(value)
  if (text.length >= 2 && text.charAt(0) === "'" && text.charAt(text.length - 1) === "'")
    return text.slice(1, -1).split("'\"'\"'").join("'")
  return text
}

// --- strings ---------------------------------------------------------------
// `imthemousenow-strings panel` output: `key='value'` lines, one per string,
// the key written exactly as locale/<code>.panel.strings writes it. Unlike
// parseEnv above there is no name transform -- the key IS the key, so a
// lookup and the file agree by inspection and tests/locale-panel.sh can
// compare the two directly.
function parseStrings(text) {
  var out = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line || line.charAt(0) === "#") continue
    var eq = line.indexOf("=")
    if (eq <= 0) continue
    out[line.slice(0, eq)] = unquote(line.slice(eq + 1))
  }
  return out
}

// One string, by key, or the English written at the call site. The same
// contract as t() in bin/imthemousenow-lib.sh, and for the same reason: the
// panel must read correctly with no strings at all -- an untranslated locale,
// a plugin directory too old to have locale/, a strings process that failed --
// so every call carries its own fallback and none of them can go blank.
function t(strings, key, fallback) {
  var value = strings ? strings[key] : undefined
  return (value === undefined || value === "") ? fallback : value
}

function envName(key) {
  return "MOUSENOW_CFG_" + String(key).replace(/[.\-]/g, "_").toUpperCase()
}

function value(settings, key, fallback) {
  var name = envName(key)
  return (settings && settings[name] !== undefined) ? settings[name] : (fallback === undefined ? "" : fallback)
}

function boolValue(settings, key) {
  return value(settings, key, "false") === "true"
}

function numberValue(settings, key, fallback) {
  var parsed = parseFloat(value(settings, key, ""))
  return isFinite(parsed) ? parsed : fallback
}

// A number for the config file. TOML distinguishes 1 from 1.0 and so does the
// setter's type check, so an int setting must not arrive with a decimal point
// and a float one must not arrive without.
function numberText(number, integer) {
  if (integer) return String(Math.round(number))
  return (Math.round(number * 100) / 100).toFixed(2)
}

// The chord line under the title: what SUPER + ; does right now, in the order
// the README names the four axes.
function chordSummary(settings) {
  if (!settings) return ""
  return [
    value(settings, "defaults.mode", "?"),
    value(settings, "defaults.scope", "?"),
    actionLabel(settings, value(settings, "defaults.action", "?")),
    value(settings, "defaults.lifetime", "?")
  ].join(" · ")
}

// An ACTION's own word, so the panel calls it whatever the OSD calls it.
function actionLabel(settings, action) {
  return value(settings, "action." + action + ".label", action)
}

// The peek's off position is a value, not an absence: 1.0 means the overlay is
// already fully drawn. Saying "off" is the only honest label for it, because
// "100%" reads like the strongest setting when it is the one that does
// nothing.
function peekText(fraction, offText) {
  if (fraction >= 1) return offText === undefined ? "off" : offText
  return percentText(fraction)
}

function percentText(fraction) {
  return String(Math.round(fraction * 100)) + "%"
}
