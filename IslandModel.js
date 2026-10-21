// Pure helpers for the Dynamic Island: glyphs, palettes, geometry per mode,
// OSD payload mapping and text formatting. No QML objects in here, so every
// function can be reasoned about (and tested) on its own.

function glyph(cp) {
  return String.fromCodePoint(cp)
}

// Phosphor Fill glyphs (MIT, bundled in fonts/), drawn in iconFont. The
// Material Design glyphs still written inline elsewhere come from
// JetBrainsMono Nerd Font through Qt's font fallback; they sit in plane 15,
// clear of Phosphor's codepoints.
var G = {
  volHigh: glyph(0xE44A),
  volMed: glyph(0xE44C),
  volLow: glyph(0xE44E),
  volMute: glyph(0xE45C),
  brightLow: glyph(0xE474),
  brightHigh: glyph(0xE472),
  play: glyph(0xE3D0),
  pause: glyph(0xE39E),
  next: glyph(0xE5A6),
  prev: glyph(0xE5A4),
  battery: glyph(0xE0C0),
  charging: glyph(0xE0BA),
  batteryAlert: glyph(0xE0C8),
  bluetooth: glyph(0xE0DA),
  headphones: glyph(0xE2A6),
  moon: glyph(0xE330),
  sun: glyph(0xE472),
  window: glyph(0xE5DA),
  coffee: glyph(0xE1C2),
  timer: glyph(0xED2C),
  stopwatch: glyph(0xE492),
  robot: glyph(0xE762),
  alarm: glyph(0xE006),
  bell: glyph(0xE0CE),
  bellOff: glyph(0xE0D4),
  music: glyph(0xE33C),
  mic: glyph(0xE326),
  micOff: glyph(0xE328),
  keyboard: glyph(0xE2D8),
  record: glyph(0xE3EE),
  wifi: glyph(0xE4EA),
  power: glyph(0xE3DA),
  check: glyph(0xE182),
  copy: glyph(0xE1CA),
  cross: glyph(0xE4F6)
}

// Apple's system colors (dark appearance). Used by the "apple" palette so the
// island reads exactly like macOS / iOS; the "theme" palette swaps them for
// the Omarchy theme's own roles.
var APPLE = {
  green: "#30D158",
  red: "#FF453A",
  orange: "#FF9F0A",
  yellow: "#FFD60A",
  blue: "#0A84FF",
  indigo: "#5E5CE6",
  purple: "#BF5AF2",
  pink: "#FF375F",
  white: "#FFFFFF",
  secondary: "#98989F"
}

function clamp(v, lo, hi) {
  return Math.max(lo, Math.min(hi, v))
}

function volumeGlyph(percent, muted) {
  if (muted || percent <= 0) return G.volMute
  if (percent < 34) return G.volLow
  if (percent < 67) return G.volMed
  return G.volHigh
}

function batteryGlyph(percent, charging) {
  if (charging) return G.charging
  if (percent <= 15) return G.batteryAlert
  return G.battery
}

// Map an `omarchy osd` payload onto an island activity. Progress payloads
// become a HUD (icon + level bar + value); message payloads become an alert
// (icon + text). Returns null for payloads the island should ignore.
// Sink descriptions are driver strings; show what a person would call them.
function friendlyOutput(d) {
  var n = d.toLowerCase()
  if (n.indexOf("sunshine") !== -1) return "Stream (Sunshine)"
  if (n.indexOf("hdmi") !== -1) { var m = d.match(/\[([^\]]+)\]/); return m ? m[1] : "HDMI Display" }
  if (n.indexOf("analog") !== -1 || n.indexOf("ryzen hd audio") !== -1) return "Laptop Speakers"
  if (n.indexOf("vw experience") !== -1) return "VW Chaser Bar"
  if (n.indexOf("easy effects") !== -1) return "Equalised Sound"
  return d
}

function osdTransient(p) {
  var key = String(p.icon || "").toLowerCase()
  var message = String(p.message || "")
  var raw = String(p.value === undefined ? "" : p.value)
  var max = Math.max(1, parseInt(p.max || "100", 10) || 100)
  var value = parseInt(raw, 10)
  var hasProgress = raw !== "" && !isNaN(value) && message === ""
  var percent = hasProgress ? clamp(Math.round(value * 100 / max), 0, 100) : -1
  var duration = parseInt(p.duration || "", 10)
  if (isNaN(duration) || duration <= 0) duration = hasProgress ? 1500 : 2200

  var icon = ""
  var tint = "white"
  var kind = "generic"
  if (key.indexOf("volume") === 0 || key === "mute" || key === "muted") {
    kind = "volume"
    icon = volumeGlyph(percent, key.indexOf("mute") !== -1)
  } else if (key.indexOf("microphone") === 0 || key.indexOf("mic") === 0) {
    kind = "mic"
    var off = key.indexOf("off") !== -1 || key.indexOf("mute") !== -1
    icon = off ? G.micOff : G.mic
    tint = off ? "red" : "orange"
  } else if (key === "brightness" || key === "display") {
    kind = "brightness"
    icon = percent >= 0 && percent < 50 ? G.brightLow : G.brightHigh
  } else if (key === "keyboard") {
    kind = "keyboard"
    icon = G.keyboard
  } else if (key.indexOf("media") === 0 || key.indexOf("player") === 0) {
    kind = "media"
    if (key.indexOf("pause") !== -1) icon = G.pause
    else if (key.indexOf("play") !== -1) icon = G.play
    else if (key.indexOf("next") !== -1) icon = G.next
    else if (key.indexOf("previous") !== -1) icon = G.prev
    else icon = G.music
  } else if (key === "power" || key === "shutdown" || key === "reboot" || key === "restart" || key === "logout") {
    kind = "power"
    icon = G.power
    tint = "red"
  } else if (key.length > 0) {
    // Callers may pass a literal glyph as the icon.
    icon = String(p.icon)
  } else if (hasProgress) {
    icon = volumeGlyph(percent, false)
  }

  if (hasProgress) {
    return { kind: "hud", source: kind, icon: icon, tint: tint, percent: percent, title: "", value: percent + "%", duration: duration }
  }
  if (message === "" && icon === "") return null
  // "omarchy audio output switch": the device name arrives as the message.
  // Show it as a centred output card, with a glyph that fits the device.
  if (kind === "volume" && message !== "") {
    var n = message.toLowerCase()
    var phones = /bud|pod|head|bluez|bluetooth|bt |wh-|wf-|earphone/.test(n)
    return { kind: "alert", source: "output", icon: phones ? G.headphones : G.volHigh, tint: "blue", title: friendlyOutput(message), value: "", duration: 2400 }
  }
  return { kind: "alert", source: kind, icon: icon, tint: tint, title: message, value: "", duration: duration }
}

// The iPhone bubble: fully rounded, no ears, and sized to its content. A
// compact live activity only grows by one icon on each side, like the
// leading/trailing views around the iPhone's camera.
// apple: the HIG's Dynamic Island sizes (393 pt wide screen): the expanded
// presentation is 371 wide and at most 160 high.
// Measured on iPhone footage: the call banner is 371 wide too (height / width 0.213).
function geometry(mode, w, h, contentWidth, apple, player) {
  var round = Math.ceil(h / 2)
  if (apple && player && mode === "expanded") return { w: 371, h: 160, rb: 44, rt: 0 }
  if (apple && mode === "incoming") { var ah2 = h + 42; return { w: 371, h: ah2, rb: Math.ceil(ah2 / 2), rt: 0 } }
  switch (mode) {
  case "compact":
    return { w: contentWidth > 0 ? contentWidth : w + (h - 2) * 2, h: h, rb: round, rt: 0 }
  case "alert":
    var ah = h + 8
    return { w: clamp(contentWidth || 0, w + (h - 2) * 2, 460), h: ah, rb: Math.ceil(ah / 2), rt: 0 }
  case "hud":
    var hh = h + 12
    return { w: w + 150, h: hh, rb: Math.ceil(hh / 2), rt: 0 }
  case "notification":
    return { w: Math.max(w + 250, contentWidth || 340), h: h + 50, rb: 24, rt: 0 }
  case "expanded":
    return { w: Math.max(w + 440, 560), h: h + 172, rb: 34, rt: 0 }
  case "incoming":
    var ih = h + 42
    return { w: Math.max(w + 300, 400), h: ih, rb: Math.ceil(ih / 2), rt: 0 }
  case "hidden":
    return { w: w, h: 0, rb: 0, rt: 0 }
  default:
    return { w: Math.max(w, contentWidth || 0), h: h, rb: round, rt: 0 }
  }
}

// Type scale, in px, named after the iOS text styles it stands in for. Every
// font size in the island is one of these; odd sizes were snapped down a step.
var TYPE = { caption2: 10, caption: 11, footnote: 12, subhead: 13, callout: 15, body: 17,
  title3: 20, title2: 22, title1: 26, large: 34, hero: 46 }

function formatTime(seconds) {
  var s = Math.max(0, Math.floor(seconds || 0))
  var h = Math.floor(s / 3600)
  var m = Math.floor((s % 3600) / 60)
  var r = s % 60
  var ss = (r < 10 ? "0" : "") + r
  if (h > 0) return h + ":" + (m < 10 ? "0" : "") + m + ":" + ss
  return m + ":" + ss
}

// MPRIS lengths are seconds in Quickshell; some players report 0 or absurd
// values for streams. Treat anything under a second as "unknown".
function validLength(len) {
  return isFinite(len) && len >= 1 && len < 60 * 60 * 24
}

// Pick the most vivid color out of a quantized palette, so the waveform
// takes the album's signature color the way iOS tints its music activity.
function vividColor(colors, fallback) {
  var best = null
  var bestScore = -1
  for (var i = 0; i < colors.length; i++) {
    var c = colors[i]
    if (!c) continue
    var max = Math.max(c.r, c.g, c.b)
    var min = Math.min(c.r, c.g, c.b)
    var sat = max === 0 ? 0 : (max - min) / max
    var score = sat * 0.7 + max * 0.3
    if (max < 0.25) score -= 0.5
    if (score > bestScore) {
      bestScore = score
      best = c
    }
  }
  if (!best || bestScore < 0.2) return fallback
  // Lift dark picks so the bars stay legible on the black island.
  var lift = Math.max(best.r, best.g, best.b)
  if (lift < 0.6) {
    var k = 0.6 / Math.max(0.01, lift)
    return Qt.rgba(Math.min(1, best.r * k), Math.min(1, best.g * k), Math.min(1, best.b * k), 1)
  }
  return best
}

function playerKey(p) {
  if (!p) return ""
  return String(p.dbusName || p.identity || "")
}

// Notification bodies can carry markup; the island shows plain text.
// The same message reaches this machine twice: phoned reads it off the phone,
// and KDE Connect mirrors the phone's own popup. Either can land first, so
// compare what they say rather than where they came from.
function sameMessage(a, b) {
  var x = plainText(a).toLowerCase()
  var y = plainText(b).toLowerCase()
  if (x === "" || y === "") return false
  if (x === y) return true
  // One side often truncates a long message, so a shared opening counts — but
  // only once there is enough of it. "Hi" and "Hi, are you there?" are two
  // different messages; sixty characters in, nobody says the same thing twice.
  var n = Math.min(x.length, y.length, 60)
  return n >= 24 && x.slice(0, n) === y.slice(0, n)
}

// True when one of the recent { body, time } entries says the same thing.
function seenRecently(recent, text, now, windowMs) {
  var list = recent || []
  for (var i = 0; i < list.length; i++) {
    if (now - list[i].time > windowMs) continue
    if (sameMessage(list[i].body, text)) return true
  }
  return false
}

// Keep the ring short: only the last few messages, only while they're fresh.
function rememberMessage(recent, text, now, windowMs) {
  var out = []
  var list = recent || []
  for (var i = 0; i < list.length; i++)
    if (now - list[i].time <= windowMs) out.push(list[i])
  out.push({ body: String(text || ""), time: now })
  return out.slice(-8)
}

function plainText(s) {
  return String(s || "")
    .replace(/<br\s*\/?>/gi, " ")
    .replace(/<[^>]*>/g, "")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, "\"")
    .replace(/&#39;/g, "'")
    .replace(/\s+/g, " ")
    .trim()
}

// ------------------------------------------------------------ child processes
// The island lives inside the long-running shell, so every program it starts
// is held to the same rules: a fixed executable in a root-owned directory
// (never a name looked up on the inherited PATH), a closed environment, a hard
// deadline that takes the whole process group down (GNU timeout signals its
// group, then KILLs it), and output capped while it is written.
var OMARCHY_BIN = "/usr/share/omarchy/bin/"
var SYSTEM_BIN = "/usr/bin/"
var SAFE_PATH = "/usr/share/omarchy/bin:/usr/bin"

function exe(name) {
  var n = String(name || "")
  if (n.indexOf("/") === 0) return n
  return (n.indexOf("omarchy-") === 0 ? OMARCHY_BIN : SYSTEM_BIN) + n
}

// The session variables the Omarchy helpers need to reach Hyprland, PipeWire,
// D-Bus and the shell, plus the user's chosen folders for screenshots and
// recordings. Nothing that names a program to run (EDITOR, BROWSER,
// OMARCHY_SCREENSHOT_EDITOR…) is passed on, and PATH is fixed.
var ENV_KEYS = ["HOME", "USER", "LOGNAME", "LANG", "XDG_RUNTIME_DIR", "WAYLAND_DISPLAY",
  "HYPRLAND_INSTANCE_SIGNATURE", "DBUS_SESSION_BUS_ADDRESS", "XDG_CURRENT_DESKTOP",
  "XDG_SESSION_TYPE", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME",
  "XDG_PICTURES_DIR", "XDG_VIDEOS_DIR", "OMARCHY_SCREENSHOT_DIR", "OMARCHY_SCREENRECORD_DIR"]

function childEnv(get) {
  var env = { PATH: SAFE_PATH, OMARCHY_PATH: "/usr/share/omarchy" }
  for (var i = 0; i < ENV_KEYS.length; i++) {
    var v = String(get(ENV_KEYS[i]) || "")
    if (v !== "" && v.length <= 4096 && !/[\u0000-\u001f]/.test(v)) env[ENV_KEYS[i]] = v
  }
  return env
}

// argv run with a deadline; stdout capped at maxBytes + 1 so an overflow is
// visible to capped(), stderr dropped. maxBytes 0 means no output at all.
function bounded(argv, seconds, maxBytes) {
  var cmd = [exe(argv[0])].concat(argv.slice(1).map(String))
  var sink = maxBytes > 0 ? "2>/dev/null | " + SYSTEM_BIN + "head -c " + (maxBytes + 1) : ">/dev/null 2>&1"
  return [SYSTEM_BIN + "timeout", "-k", "2", String(seconds), SYSTEM_BIN + "bash", "-c",
          "set -o pipefail; \"$@\" " + sink, "bounded"].concat(cmd)
}

// A long-lived program the user started on purpose (a screen recording, the
// update terminal): fixed executable and closed environment, no deadline.
function direct(argv) {
  return [exe(argv[0])].concat(argv.slice(1).map(String))
}

// Upper bound on the UTF-8 size of s (invalid bytes decode to U+FFFD, three
// bytes, so this never undercounts).
function utf8Length(s) {
  var t = String(s || "")
  var n = 0
  for (var i = 0; i < t.length; i++) {
    var c = t.charCodeAt(i)
    n += c < 0x80 ? 1 : c < 0x800 ? 2 : (c >= 0xd800 && c <= 0xdbff) ? (i++, 4) : 3
  }
  return n
}

// Collected output, or null when the producer went past its cap.
function capped(text, maxBytes) {
  var t = String(text || "")
  return utf8Length(t) > maxBytes ? null : t
}

// Strings that reach the island from outside (IPC, device names, messages)
// are shortened before they are laid out.
function clip(s, n) {
  var t = String(s === undefined || s === null ? "" : s).replace(/[\u0000-\u0008\u000b-\u001f\u007f]/g, "")
  return t.length > n ? t.slice(0, n - 1) + "…" : t
}

// Image sources the island will load: local files, and the shell's own
// in-process image providers (themed icons, tray pixmaps). Anything else
// (http, https, data:, qrc:) would make the shell fetch or decode something
// the island never checked, so it falls back to the glyph.
function localImage(u) {
  var s = String(u || "")
  if (s === "") return ""
  if (/^image:\/\/[A-Za-z]+\//.test(s)) return s
  var path = s.indexOf("file://") === 0 ? s.slice(7) : s
  if (path.indexOf("/") !== 0 || /(^|\/)\.\.(\/|$)/.test(path) || /[\u0000-\u001f]/.test(path)) return ""
  if (/^\/(dev|proc|sys)\//.test(path)) return ""
  return "file://" + path
}

function weekStrip(now) {
  var d = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  var dow = (d.getDay() + 6) % 7 // Monday first
  var start = new Date(d.getTime() - dow * 86400000)
  var names = ["M", "T", "W", "T", "F", "S", "S"]
  var out = []
  for (var i = 0; i < 7; i++) {
    var day = new Date(start.getTime() + i * 86400000)
    out.push({ label: names[i], day: day.getDate(), today: i === dow })
  }
  return out
}

// One cava frame ("12;40;7;...;") as levels in 0..1, or null when the line is
// not a frame of exactly `bars` numbers.
function parseSpectrum(line, bars) {
  var parts = String(line || "").split(";")
  if (parts.length && parts[parts.length - 1] === "") parts.pop()
  if (parts.length !== bars) return null
  var out = []
  for (var i = 0; i < bars; i++) {
    if (!/^\d{1,3}$/.test(parts[i])) return null
    out.push(Math.min(100, Number(parts[i])) / 100)
  }
  return out
}

// Next moment the wall clock reads "H:MM" (24-hour), as epoch ms after nowMs;
// 0 when the text is not a time.
function nextAlarm(hhmm, nowMs) {
  var m = /^([01]?\d|2[0-3]):([0-5]\d)$/.exec(String(hhmm || "").trim())
  if (!m) return 0
  var d = new Date(nowMs)
  d.setHours(Number(m[1]), Number(m[2]), 0, 0)
  if (d.getTime() <= nowMs) d.setDate(d.getDate() + 1)
  return d.getTime()
}

// A saved alarm (epoch ms as text) if it is still ahead and within a day.
function restoredAlarm(text, nowMs) {
  var t = String(text || "").trim()
  if (!/^\d{1,15}$/.test(t)) return 0
  var at = Number(t)
  return at > nowMs && at - nowMs <= 24 * 3600 * 1000 ? at : 0
}

function clockText(ms) {
  var d = new Date(ms)
  return (d.getHours() < 10 ? "0" : "") + d.getHours() + ":" + (d.getMinutes() < 10 ? "0" : "") + d.getMinutes()
}

// LRC text ("[01:23.45] words") as [{ t: seconds, text }] sorted by time.
function parseLrc(lrc) {
  var out = []
  var lines = String(lrc || "").split(/\r?\n/)
  for (var i = 0; i < lines.length && out.length < 2000; i++) {
    var m = /^\[(\d{1,3}):(\d{2}(?:\.\d{1,3})?)\]\s*(.*)$/.exec(lines[i])
    if (m) out.push({ t: Number(m[1]) * 60 + Number(m[2]), text: clip(m[3], 200).trim() })
  }
  out.sort(function(a, b) { return a.t - b.t })
  return out
}

// The line being sung at pos seconds; "" before the first line or between verses.
function lyricAt(lines, pos) {
  var cur = ""
  for (var i = 0; i < lines.length && lines[i].t <= pos; i++) cur = lines[i].text
  return cur
}

// SVG path of a w x h rectangle with continuous-curvature ("squircle")
// corners, as iOS draws them: Figma's corner smoothing (0.6 is iOS). Where
// the radius runs out of room the smoothing shrinks, so a capsule stays an
// exact capsule.
function squirclePath(w, h, r, smoothing) {
  w = Math.max(0, w); h = Math.max(0, h)
  var budget = Math.min(w, h) / 2
  r = Math.max(0, Math.min(r, budget))
  var s = Math.max(0, smoothing || 0)
  var p = (1 + s) * r
  if (p > budget) { s = r > 0 ? Math.max(0, Math.min(s, budget / r - 1)) : 0; p = Math.min(p, budget) }
  var rad = Math.PI / 180
  var arcMeasure = 90 * (1 - s)
  var arc = Math.sin(arcMeasure / 2 * rad) * r * Math.SQRT2
  var alpha = (90 - arcMeasure) / 2
  var p34 = r * Math.tan(alpha / 2 * rad)
  var beta = 45 * s
  var c = p34 * Math.cos(beta * rad)
  var d = c * Math.tan(beta * rad)
  var b = Math.max(0, (p - arc - c - d) / 3)
  var a = 2 * b
  function n(v) { return (Math.round(v * 100) / 100).toString() }
  var abc = a + b + c, bc = b + c
  return "M " + n(w - p) + " 0" +
    " c " + n(a) + " 0 " + n(a + b) + " 0 " + n(abc) + " " + n(d) +
    " a " + n(r) + " " + n(r) + " 0 0 1 " + n(arc) + " " + n(arc) +
    " c " + n(d) + " " + n(c) + " " + n(d) + " " + n(bc) + " " + n(d) + " " + n(abc) +
    " L " + n(w) + " " + n(h - p) +
    " c 0 " + n(a) + " 0 " + n(a + b) + " " + n(-d) + " " + n(abc) +
    " a " + n(r) + " " + n(r) + " 0 0 1 " + n(-arc) + " " + n(arc) +
    " c " + n(-c) + " " + n(d) + " " + n(-bc) + " " + n(d) + " " + n(-abc) + " " + n(d) +
    " L " + n(p) + " " + n(h) +
    " c " + n(-a) + " 0 " + n(-(a + b)) + " 0 " + n(-abc) + " " + n(-d) +
    " a " + n(r) + " " + n(r) + " 0 0 1 " + n(-arc) + " " + n(-arc) +
    " c " + n(-d) + " " + n(-c) + " " + n(-d) + " " + n(-bc) + " " + n(-d) + " " + n(-abc) +
    " L 0 " + n(p) +
    " c 0 " + n(-a) + " 0 " + n(-(a + b)) + " " + n(d) + " " + n(-abc) +
    " a " + n(r) + " " + n(r) + " 0 0 1 " + n(arc) + " " + n(-arc) +
    " c " + n(c) + " " + n(-d) + " " + n(bc) + " " + n(-d) + " " + n(abc) + " " + n(-d) + " Z"
}

// What a drag or two-finger swipe on the island means. dx/dy in pixels
// (touchpad: accumulated angle delta / 4). Sideways on a live activity
// tucks it; upward on a transient sends it away. Short or diagonal moves
// are clicks and scrolls, not swipes.
var SWIPE_MIN = 36
function swipeAction(dx, dy, mode) {
  var ax = Math.abs(dx), ay = Math.abs(dy)
  if (mode === "compact" && ax >= SWIPE_MIN && ax > 2 * ay) return "tuck"
  if ((mode === "notification" || mode === "alert" || mode === "hud") && dy <= -SWIPE_MIN && ay > 2 * ax) return "dismiss"
  return ""
}

// One-time codes. A candidate is 4 to 8 digits standing on its own: nothing of a word, a card tail (XX1234), a
// masked or hashed number (*9340, #1234), a date, a time or a decimal touches it, no currency comes before it, and
// it is not 1930, the fraud helpline banks print in every message. Of the candidates, the one nearest a code word
// wins, on either side: "413174 is your OTP", "your code is 413174", "ending in 1234 with code 567890".
// No lookbehind anywhere: Qt's JS engine accepts it and then never matches, silently. The text before a run is
// checked by hand instead (run tests/run.sh, which tests in Qt's engine as well as Node's).
var OTP_WORD = /\b(otp|one[- ]time|code|passcode|pin|verification|verify)\b/gi
var OTP_NUM = /\d{4,8}/g
function otpCode(text) {
  var t = String(text || "")
  var words = [], m
  OTP_WORD.lastIndex = 0
  while ((m = OTP_WORD.exec(t)) !== null) words.push([m.index, m.index + m[0].length])
  if (words.length === 0) return ""
  var best = "", gap = Infinity
  OTP_NUM.lastIndex = 0
  while ((m = OTP_NUM.exec(t)) !== null) {
    var a = m.index, b = a + m[0].length
    var before = t.slice(Math.max(0, a - 6), a), after = t.slice(b, b + 2)
    if (/[\w*#+:\/-]$/.test(before) || /\d[.,]$/.test(before) || /(?:rs|inr|₹)[.:]?\s?$/i.test(before)) continue
    if (/^[\w*#:\/-]/.test(after) || /^[.,]\d/.test(after) || m[0] === "1930") continue
    for (var i = 0; i < words.length; i++) {
      var g = words[i][0] >= b ? words[i][0] - b : a - words[i][1]
      if (g < gap) { gap = g; best = m[0] }
    }
  }
  return best
}
// How long the message says the code lasts, in minutes; 0 when it does not say.
function otpMinutes(text) {
  var m = /valid(?:\s+(?:for|till|upto|up to))?\s+(\d{1,2})\s*(?:min|mins|minutes)\b/i.exec(String(text || ""))
  return m ? Number(m[1]) : 0
}
// The code as it reads best: 413 174, 4131 7412; other lengths as they are.
function otpGroup(code) {
  var c = String(code || "")
  return c.length === 6 ? c.slice(0, 3) + " " + c.slice(3) : c.length === 8 ? c.slice(0, 4) + " " + c.slice(4) : c
}

// A notification's own click action: Omarchy's omarchy-exec-argv hint, a JSON array of strings, kept in its file.
// Null for anything else (empty, not JSON, not all strings, absurdly long), so a bad hint is never run.
function execArgvOf(v) {
  var a
  try { a = JSON.parse(String(v || "")) } catch (e) { return null }
  if (!Array.isArray(a) || a.length === 0 || a.length > 64) return null
  for (var i = 0; i < a.length; i++)
    if (typeof a[i] !== "string" || a[i].length > 4096 || /[\u0000]/.test(a[i])) return null
  return a[0] !== "" ? a : null
}

// Android hides a notification that holds a code from companion apps; KDE Connect then relays only this line.
function isRedacted(n) {
  return /^\s*sensitive notification content hidden\s*$/i.test(String((n && (n.fullText || n.body)) || ""))
}

// One line of `nmcli -t` output as its fields: ":" separates them, "\\:" is a colon inside one (an SSID "Cafe:5G").
function nmcliFields(line) {
  return String(line || "").replace(/\\:/g, "\u0001").split(":").map(function(f) { return f.replace(/\u0001/g, ":") })
}

// ---- Ride, food and delivery notifications as one live "trip" card.
// tripFrom(n) reads one notification ({app, title, body, time}) and says what it
// tells about a trip in flight: { type, app, stage 1..3, etaMin (-1 when unknown),
// text }, { done: true } when the trip is over, or null when it is not a trip.
// No lookbehind: Qt's regex engine accepts it and then never matches.
var TRIP_APPS = [
  ["ride", /uber|ola\b|ola cabs|rapido|indrive|bolt|lyft|namma yatri/i],
  ["food", /zomato|swiggy|domino|mcdonald|eatsure|burger king|kfc|pizza hut|starbucks|zepto cafe/i],
  ["flight", /indigo|air india|vistara|akasa|spicejet|airasia|emirates|qatar airways|etihad|lufthansa|british airways|singapore airlines|ixigo|makemytrip|cleartrip|easemytrip|flightradar|flightaware|digiyatra/i],
  ["sports", /cricbuzz|cricinfo|espn|sofascore|fotmob|onefootball|dream11|jiocinema|hotstar|sony liv|sportstar|goal\.com|premier league|uefa|nba|ipl/i],
  ["delivery", /amazon|flipkart|blinkit|zepto|instamart|bigbasket|myntra|meesho|delhivery|ekart|bluedart|dunzo|shadowfax|ecom express|xpressbees/i]
]
var TRIP_AGE = { ride: 90 * 60000, food: 90 * 60000, delivery: 90 * 60000, flight: 12 * 3600000, sports: 4 * 3600000 }
var TRIP_SCORE = /\b(\d{1,3})\s*\/\s*(\d{1,2})\b|\b(\d{1,2})\s*[-:]\s*(\d{1,2})\b/
var TRIP_SPORTS_DONE = /won by|match (?:ended|over|tied|drawn|abandoned)|full[- ]time|final result|stumps|\bFT\b/i
var TRIP_SPORTS_LIVE = /live|wicket|sixes|six\b|four\b|goal|toss|kick[- ]?off|half[- ]time|innings|over\b|overs\b/i
var TRIP_FLIGHT_DONE = /landed|baggage|belt \d|arrived at/i
var TRIP_HOURS = /(\d{1,2})\s*(?:h|hr|hrs|hour|hours)\b(?:\s*(\d{1,2})\s*(?:m|min|mins)\b)?/i
var TRIP_DONE = /delivered|has been delivered|completed|trip ended|ride ended|you have arrived|payment received|rate your|cancel+ed|refund/i
var TRIP_ETA = /(\d{1,3})\s*(?:-\s*\d{1,3}\s*)?(?:min|mins|minute|minutes)\b/i
var TRIP_STAGE3 = /arriving now|has arrived|is here|reached|at your (?:door|location)|arrived/i
var TRIP_STAGE2 = /picked up|on the way|on its way|out for delivery|en route|heading|driver is|rider is|captain is|arriving|nearby/i
var TRIP_STAGE1 = /confirmed|accepted|preparing|being prepared|placed|packed|shipped|dispatched|assigned|looking for|searching|locating/i

function tripFrom(n) {
  if (!n) return null
  var app = String(n.app || "")
  var type = ""
  for (var i = 0; i < TRIP_APPS.length; i++) if (TRIP_APPS[i][1].test(app)) { type = TRIP_APPS[i][0]; break }
  if (type === "") return null
  var text = String(n.title || "") + " " + String(n.body || "")
  if (type === "sports") {
    if (TRIP_SPORTS_DONE.test(text)) return { done: true, app: app, type: type }
    var sm = TRIP_SCORE.exec(text)
    if (!sm && !TRIP_SPORTS_LIVE.test(text)) return null
    return { type: type, app: app, stage: 0, etaMin: -1, score: sm ? sm[0].replace(/\s+/g, "") : "", text: String(n.title || "").trim() || String(n.body || "").trim() }
  }
  if (type === "flight") {
    if (TRIP_FLIGHT_DONE.test(text)) return { done: true, app: app, type: type }
    var fs = /took off|departed|in the air|airborne|en route/i.test(text) ? 3 : /boarding|gate/i.test(text) ? 2 : /check-?in|web check|boarding pass|confirmed|on time|delayed|departs|departure/i.test(text) ? 1 : 0
    var hm = TRIP_HOURS.exec(text)
    var fm = TRIP_ETA.exec(text)
    var fe = hm ? Number(hm[1]) * 60 + Number(hm[2] || 0) : fm ? Number(fm[1]) : -1
    if (fs === 0 && fe < 0) return null
    return { type: type, app: app, stage: fs || 1, etaMin: fe, text: String(n.title || "").trim() || String(n.body || "").trim() }
  }
  if (TRIP_DONE.test(text)) return { done: true, app: app, type: type }
  var stage = TRIP_STAGE3.test(text) ? 3 : TRIP_STAGE2.test(text) ? 2 : TRIP_STAGE1.test(text) ? 1 : 0
  var m = TRIP_ETA.exec(text)
  var eta = m ? Number(m[1]) : -1
  // An ordinary offer or receipt from a shop app is not a trip.
  if (stage === 0 && eta < 0) return null
  if (stage === 0) stage = 1
  return { type: type, app: app, stage: stage, etaMin: eta, text: String(n.title || "").trim() || String(n.body || "").trim() }
}

// The trip to show from a newest-first history: the first trip notification within
// maxAgeMs that no later "done" for the same app has closed, and that was not hidden.
function currentTrip(history, now, maxAgeMs, hiddenAt) {
  var closed = {}
  for (var i = 0; i < history.length; i++) {
    var n = history[i]
    var t = Number(n.time) || 0
    var r = tripFrom(n)
    if (!r) continue
    if (now - t > (maxAgeMs > 0 ? maxAgeMs : TRIP_AGE[r.type]) || t <= (hiddenAt || 0)) continue
    if (r.done) { closed[r.app] = true; continue }
    if (closed[r.app]) continue
    r.time = t
    r.etaAt = r.etaMin >= 0 ? t + r.etaMin * 60000 : 0
    return r
  }
  return null
}

// "2h 10m" or "45 min" for the minutes left.
function minutesText(m) {
  if (m < 0) return ""
  return m >= 60 ? Math.floor(m / 60) + "h " + (m % 60) + "m" : m + " min"
}
