// Pure helpers for the Dynamic Island: glyphs, palettes, geometry per mode,
// OSD payload mapping and text formatting. No QML objects in here, so every
// function can be reasoned about (and tested) on its own.

function glyph(cp) {
  return String.fromCodePoint(cp)
}

// Nerd Font (Material Design) glyphs. Omarchy ships JetBrainsMono Nerd Font.
var G = {
  volHigh: glyph(0xF057E),
  volMed: glyph(0xF0580),
  volLow: glyph(0xF057F),
  volMute: glyph(0xF075F),
  brightLow: glyph(0xF00DE),
  brightHigh: glyph(0xF00E0),
  play: glyph(0xF040A),
  pause: glyph(0xF03E4),
  next: glyph(0xF04AD),
  prev: glyph(0xF04AE),
  battery: glyph(0xF0079),
  charging: glyph(0xF0084),
  batteryAlert: glyph(0xF0083),
  bluetooth: glyph(0xF00AF),
  headphones: glyph(0xF02CB),
  moon: glyph(0xF0594),
  timer: glyph(0xF051B),
  bell: glyph(0xF009A),
  bellOff: glyph(0xF009B),
  music: glyph(0xF075A),
  mic: glyph(0xF036C),
  micOff: glyph(0xF036D),
  keyboard: glyph(0xF030C),
  record: glyph(0xF044A),
  wifi: glyph(0xF05A9),
  power: glyph(0xF0425)
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
  return { kind: "alert", source: kind, icon: icon, tint: tint, title: message, value: "", duration: duration }
}

// Island geometry per mode. `h` is the notch height (the bar height, like the
// MacBook notch which is exactly as tall as the menu bar) and `w` the notch
// width. Values mirror the proportions of the macOS Dynamic Island apps and
// the SketchyBar reference (expand height ≈ 1.5× notch for HUDs, ≈ 2.3× for
// music info, ≈ 7× for the full player).
function geometry(mode, w, h, contentWidth, pill) {
  if (pill) return pillGeometry(mode, w, h, contentWidth)
  var side = h + 12
  switch (mode) {
  case "compact":
    return { w: w + side * 2, h: h, rb: Math.round(h * 0.42), rt: 6 }
  case "alert":
    return { w: Math.max(w + 150, Math.min(560, contentWidth || 0)), h: h + 14, rb: Math.round((h + 14) * 0.45), rt: 7 }
  case "hud":
    return { w: w + 170, h: h + 38, rb: 20, rt: 8 }
  case "notification":
    return { w: Math.max(w + 210, 420), h: h + 68, rb: 26, rt: 9 }
  case "expanded":
    return { w: Math.max(w + 380, 600), h: h + 174, rb: 32, rt: 10 }
  case "incoming":
    return { w: Math.max(w + 250, 440), h: h + 56, rb: 30, rt: 9 }
  case "hidden":
    return { w: w, h: 0, rb: 0, rt: 0 }
  default:
    return { w: w, h: h, rb: Math.round(h * 0.42), rt: 6 }
  }
}

// The iPhone bubble: fully rounded, no ears, and sized to its content. A
// compact live activity only grows by one icon on each side, like the
// leading/trailing views around the iPhone's camera.
function pillGeometry(mode, w, h, contentWidth) {
  var round = Math.ceil(h / 2)
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
    return { w: Math.max(w + 250, 340), h: h + 50, rb: 24, rt: 0 }
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

if (typeof module !== "undefined") {
  module.exports = {
    G: G, APPLE: APPLE, clamp: clamp, volumeGlyph: volumeGlyph, batteryGlyph: batteryGlyph,
    osdTransient: osdTransient, geometry: geometry, pillGeometry: pillGeometry, formatTime: formatTime,
    validLength: validLength, vividColor: vividColor, playerKey: playerKey,
    plainText: plainText, weekStrip: weekStrip
  }
}
