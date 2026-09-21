import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import Quickshell.Bluetooth
import Quickshell.Hyprland
import qs.Commons
import "IslandModel.js" as Model

// Dynamic Island service. Owns every piece of shared state — media, the
// activity queue (HUDs, alerts, notification peeks), live activities
// (music, timer, screen recording) — and mounts one notch window per
// monitor. The windows only decide how to draw that state and track their
// own hover/expanded state.
Item {
  id: root

  property var shell: null
  property var manifest: null
  readonly property string pluginId: "io.github.buildscript-dev.dynamic-island"

  // ------------------------------------------------------------ settings
  // Settings live on the island's bar entry in shell.json, like every other
  // bar widget, so the Omarchy settings UI and `updateEntryInline` apply.
  // The shell's public barConfig snapshot only refreshes on plugin-registry
  // events, so the island reads shell.json itself to apply edits instantly.
  property var liveBarConfig: null
  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var parsed = JSON.parse(text() || "{}")
        root.liveBarConfig = parsed && parsed.bar ? parsed.bar : null
      } catch (e) {}
    }
  }
  readonly property var settings: {
    var cfg = root.liveBarConfig || (root.shell ? root.shell.barConfig : null)
    var layout = cfg && cfg.layout ? cfg.layout : {}
    var sections = ["center", "left", "right"]
    for (var i = 0; i < sections.length; i++) {
      var list = layout[sections[i]] || []
      for (var j = 0; j < list.length; j++)
        if (list[j] && list[j].id === root.pluginId) return list[j]
    }
    return {}
  }
  function setting(name, fallback) {
    var v = root.settings[name]
    return v === undefined || v === null || v === "" ? fallback : v
  }

  readonly property string style: String(setting("style", "black"))           // black | bar | glass
  readonly property string palette: String(setting("palette", "apple"))       // apple | theme
  // pill: a floating iPhone-style bubble inside the bar · notch: a MacBook
  // notch hanging from the top edge.
  readonly property string shape: String(setting("shape", "pill"))
  readonly property bool pill: shape !== "notch"
  readonly property int notchWidth: pill ? Number(setting("islandWidth", 96)) : Number(setting("notchWidth", 200))
  readonly property bool openOnHover: setting("openOnHover", true) === true
  readonly property int hoverDelay: Number(setting("hoverDelay", 320))
  readonly property bool showNotifications: setting("showNotifications", true) === true
  readonly property bool replaceOsd: setting("replaceOsd", true) === true
  readonly property bool hideInFullscreen: setting("hideInFullscreen", true) === true
  // On by default the island always sits there. Turn it off and it tucks
  // away with nothing to show, sliding back in for anything live (or when
  // the pointer touches the top-center edge) — the standalone, no-bar look.
  readonly property bool showWhenIdle: setting("showWhenIdle", true) === true
  // One switch for everything that reaches the network: album artwork for
  // streaming players, the weather line, and the Omarchy update check.
  readonly property bool onlineExtras: setting("onlineExtras", true) === true
  readonly property bool showWorkspaces: setting("showWorkspaces", true) === true
  readonly property bool artworkTint: setting("artworkTint", true) === true
  readonly property bool showMicIndicator: setting("showMicIndicator", true) === true
  readonly property bool scrollVolume: setting("scrollVolume", true) === true
  // external: the external monitor when one is plugged in, otherwise the
  // built-in display · focused: follows the focused monitor · all: one per
  // monitor · or a connector name such as HDMI-A-1.
  readonly property string monitor: String(setting("monitor", "focused"))
  function isInternal(name) { return /^(eDP|LVDS|DSI)-/.test(String(name || "")) }
  readonly property string preferredScreen: {
    var all = Quickshell.screens
    var internal = ""
    for (var i = 0; i < all.length; i++) {
      var n = String(all[i].name || "")
      if (!isInternal(n)) return n
      if (internal === "") internal = n
    }
    return internal
  }

  // ------------------------------------------------------------ bar geometry
  readonly property var barConfig: root.liveBarConfig || (root.shell && root.shell.barConfig ? root.shell.barConfig : ({}))
  readonly property string barPosition: String(barConfig.position || "top")
  // The notch is exactly as tall as the menu bar, like on a MacBook.
  readonly property int barHeight: barPosition === "top" ? Style.bar.sizeHorizontal : Math.max(26, Style.bar.sizeHorizontal)
  // The pill floats inside the bar with a small inset all round, centered
  // on the bar's own widgets; the notch is exactly as tall as the bar.
  // The pill floats a little below the top edge, iPhone-style, at its own
  // height (it no longer has a bar to fit inside); the notch matches the bar.
  readonly property int islandTop: pill ? Math.max(0, Number(setting("pillInset", 6))) : 0
  readonly property int notchHeight: pill ? Math.max(20, Number(setting("islandHeight", 30))) : barHeight

  // ------------------------------------------------------------ look
  readonly property color islandColor: style === "bar" ? Color.bar.background
    : style === "glass" ? Qt.rgba(0, 0, 0, 0.62)
    : "#000000"
  readonly property color textColor: style === "bar" ? Color.bar.text : "#ffffff"
  readonly property color secondaryText: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.58)
  readonly property color trackColor: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.18)
  readonly property color controlFill: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.1)

  function tint(name) {
    if (palette === "theme") {
      if (name === "red") return Color.urgent
      if (name === "white" || name === "") return root.textColor
      return Color.accent
    }
    if (name === "white" || name === "") return root.textColor
    return Model.APPLE[name] || root.textColor
  }

  readonly property string textFont: {
    var want = ["SF Pro Display", "SF Pro Text", "SF Pro", "Inter Display", "Inter", "Inter Variable", "Noto Sans", "Cantarell"]
    var have = Qt.fontFamilies()
    for (var i = 0; i < want.length; i++)
      if (have.indexOf(want[i]) !== -1) return want[i]
    return Style.font.family
  }
  readonly property string iconFont: {
    var have = Qt.fontFamilies()
    if (have.indexOf("JetBrainsMono Nerd Font") !== -1) return "JetBrainsMono Nerd Font"
    if (have.indexOf("Symbols Nerd Font") !== -1) return "Symbols Nerd Font"
    return Style.font.family
  }

  readonly property var glyphs: Model.G

  // Ticks once a second for clocks, timers and progress.
  property date now: new Date()
  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.now = new Date()
  }

  // Events fired during startup (initial Bluetooth / battery / DND state) are
  // state loads, not changes; the island only reacts once the grace passes.
  property bool settled: false
  Timer {
    interval: 3500
    running: true
    onTriggered: root.settled = true
  }

  // ------------------------------------------------------------ media
  readonly property var players: Mpris.players ? Mpris.players.values : []
  // Plain JS object: remembering the last player must not re-trigger the
  // bindings that read it (that was a binding loop).
  readonly property var playerMemory: ({ key: "" })
  readonly property string lastPlayerKey: playerMemory.key
  readonly property var playingPlayer: {
    var first = null
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (!p || !p.isPlaying) continue
      if (!first) first = p
      if (root.playerMemory.key !== "" && Model.playerKey(p) === root.playerMemory.key) return p
    }
    return first
  }
  onPlayingPlayerChanged: if (playingPlayer) playerMemory.key = Model.playerKey(playingPlayer)
  readonly property var player: {
    if (root.playingPlayer) return root.playingPlayer
    var fallback = null
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (!p || !(p.trackTitle || p.trackArtist)) continue
      if (Model.playerKey(p) === root.playerMemory.key) return p
      if (!fallback) fallback = p
    }
    return fallback
  }
  readonly property bool hasMedia: player !== null && !!(player.trackTitle || player.trackArtist)
  readonly property bool isPlaying: player ? !!player.isPlaying : false
  readonly property string trackTitle: player ? String(player.trackTitle || "") : ""
  readonly property string trackArtist: player ? String(player.trackArtist || "") : ""
  readonly property string trackAlbum: player ? String(player.trackAlbum || "") : ""
  readonly property string trackArt: player ? String(player.trackArtUrl || "") : ""
  readonly property real trackLength: player && Model.validLength(player.length) ? player.length : 0
  readonly property string playerName: player ? String(player.identity || "") : ""
  readonly property string playerIcon: {
    if (!player) return ""
    var id = String(player.desktopEntry || "")
    var entry = id ? DesktopEntries.byId(id) : null
    var icon = entry && entry.icon ? entry.icon : id
    return icon ? Quickshell.iconPath(icon, true) : ""
  }

  // MPRIS position isn't pushed; poll it only while something shows it.
  property real trackPosition: 0
  property int positionWatchers: 0
  Timer {
    interval: 500
    repeat: true
    running: root.player !== null && root.positionWatchers > 0
    triggeredOnStart: true
    onTriggered: {
      if (!root.player) return
      root.player.positionChanged()
      root.trackPosition = root.player.position
    }
  }

  // Paused music lingers as a live activity for a moment, then the island
  // settles back to the bare notch — like macOS notch apps do.
  property bool pausedLinger: false
  onIsPlayingChanged: {
    if (isPlaying) {
      pausedLingerTimer.stop()
      pausedLinger = false
    } else if (hasMedia) {
      pausedLinger = true
      pausedLingerTimer.restart()
    }
  }
  Timer {
    id: pausedLingerTimer
    interval: 6000
    onTriggered: root.pausedLinger = false
  }
  readonly property bool mediaLive: hasMedia && (isPlaying || pausedLinger)

  // The quantizer only reads local files; streaming players (Spotify) hand
  // out https artwork, so fetch it once into a small cache first.
  property string artLocal: ""
  onTrackArtChanged: fetchArt()
  onArtworkTintChanged: fetchArt()
  Component.onCompleted: fetchArt()
  function fetchArt() {
    artLocal = ""
    if (trackArt === "" || !artworkTint) return
    if (trackArt.indexOf("http") !== 0) { artLocal = trackArt; return }
    // Remote artwork is the only download the island itself makes.
    if (!onlineExtras) return
    artFetch.running = false
    artFetch.command = ["sh", "-c",
      "d=\"${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-dynamic-island\"; mkdir -p \"$d\"; " +
      "find \"$d\" -type f -mtime +7 -delete 2>/dev/null; " +
      "f=\"$d/$(printf %s \"$1\" | md5sum | cut -c1-20).img\"; " +
      "[ -s \"$f\" ] || curl -fsL --max-time 8 -o \"$f\" \"$1\" || exit 1; printf %s \"$f\"",
      "sh", trackArt]
    artFetch.running = true
  }
  Process {
    id: artFetch
    stdout: StdioCollector {
      onStreamFinished: {
        var p = String(text || "").trim()
        if (p !== "") root.artLocal = "file://" + p
      }
    }
  }

  ColorQuantizer {
    id: artQuantizer
    source: root.artLocal
    depth: 2
    rescaleSize: 48
  }
  readonly property color mediaAccent: artworkTint && trackArt !== ""
    ? Model.vividColor(artQuantizer.colors, tint("white"))
    : (palette === "theme" ? Color.accent : tint("white"))

  function mediaToggle() {
    var p = root.player
    if (!p) return
    if (p.isPlaying) { if (p.canPause) p.pause() }
    else if (p.canPlay) p.play()
  }
  function mediaNext() { if (root.player && root.player.canGoNext) root.player.next() }
  function mediaPrev() {
    var p = root.player
    if (!p) return
    // Apple behavior: "previous" restarts the track unless you're at the start.
    if (p.canSeek && root.trackPosition > 4) { p.position = 0; root.trackPosition = 0 }
    else if (p.canGoPrevious) p.previous()
  }
  function mediaSeek(fraction) {
    var p = root.player
    if (!p || !p.canSeek || root.trackLength <= 0) return
    var pos = Model.clamp(fraction, 0, 1) * root.trackLength
    p.position = pos
    root.trackPosition = pos
  }
  function mediaRaise() { if (root.player && root.player.canRaise) root.player.raise() }

  // ------------------------------------------------------------ timer
  property real timerEnd: 0        // epoch ms; 0 = no timer
  property real timerTotal: 0      // seconds
  property real timerPausedLeft: -1
  readonly property bool timerActive: timerEnd > 0 || timerPausedLeft >= 0
  readonly property real timerLeft: {
    root.now
    if (timerPausedLeft >= 0) return timerPausedLeft
    return timerEnd > 0 ? Math.max(0, (timerEnd - Date.now()) / 1000) : 0
  }
  function startTimer(seconds) {
    var s = Math.max(1, Math.round(Number(seconds) || 0))
    timerTotal = s
    timerPausedLeft = -1
    timerEnd = Date.now() + s * 1000
    root.now = new Date()
    pushActivity({ kind: "alert", source: "timer", icon: glyphs.timer, tint: "orange", title: "Timer", value: Model.formatTime(s), duration: 1600 })
  }
  function addTimer(seconds) {
    if (!timerActive) { startTimer(seconds); return }
    if (timerPausedLeft >= 0) timerPausedLeft += seconds
    else timerEnd += seconds * 1000
    timerTotal += seconds
    root.now = new Date()
  }
  function toggleTimerPause() {
    if (!timerActive) return
    if (timerPausedLeft >= 0) {
      timerEnd = Date.now() + timerPausedLeft * 1000
      timerPausedLeft = -1
    } else {
      timerPausedLeft = timerLeft
      timerEnd = 0
    }
    root.now = new Date()
  }
  function cancelTimer() {
    timerEnd = 0
    timerPausedLeft = -1
    timerTotal = 0
  }
  Timer {
    interval: 250
    repeat: true
    running: root.timerEnd > 0
    onTriggered: {
      if (Date.now() >= root.timerEnd) {
        root.cancelTimer()
        root.pushActivity({ kind: "alert", source: "timer-done", icon: root.glyphs.timer, tint: "orange", title: "Timer Done", value: "", duration: 6000 })
        chime.running = true
      }
    }
  }
  Process {
    id: chime
    command: ["sh", "-c", "for f in /usr/share/sounds/freedesktop/stereo/complete.oga /usr/share/sounds/freedesktop/stereo/bell.oga; do [ -f \"$f\" ] && exec pw-play \"$f\"; done; exit 0"]
  }

  // ------------------------------------------------------------ recording
  property bool recording: false
  property real recordingSince: 0
  Timer {
    interval: 2500
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: if (!recProc.running) recProc.running = true
  }
  Process {
    id: recProc
    command: ["pgrep", "--quiet", "-f", "^gpu-screen-recorder"]
    onExited: function(code) {
      var on = code === 0
      if (on && !root.recording) root.recordingSince = Date.now()
      root.recording = on
    }
  }
  function stopRecording() {
    Quickshell.execDetached(["omarchy-capture-screenrecording", "--stop-recording"])
  }

  // ------------------------------------------------------------ microphone privacy dot
  readonly property bool micInUse: {
    if (!root.showMicIndicator) return false
    var nodes = Pipewire.nodes ? Pipewire.nodes.values : []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (!n || !n.isStream) continue
      var props = n.properties || {}
      if (props["media.class"] === "Stream/Input/Audio" && props["stream.monitor"] !== "true") return true
    }
    return false
  }

  // ------------------------------------------------------------ battery
  readonly property var battery: UPower.displayDevice
  readonly property bool hasBattery: battery && battery.isLaptopBattery
  readonly property int batteryPercent: {
    if (!battery) return 0
    var p = Number(battery.percentage || 0)
    return Math.round(p <= 1 ? p * 100 : p)
  }
  readonly property bool onBattery: UPower.onBattery
  readonly property bool charging: hasBattery && !onBattery
  onOnBatteryChanged: {
    if (!settled || !hasBattery) return
    if (onBattery)
      pushActivity({ kind: "alert", source: "power", icon: Model.batteryGlyph(batteryPercent, false), tint: batteryPercent <= 20 ? "red" : "white", title: "On Battery", value: batteryPercent + "%", duration: 2200 })
    else
      pushActivity({ kind: "alert", source: "power", icon: glyphs.charging, tint: "green", title: "Charging", value: batteryPercent + "%", duration: 2600 })
  }
  property int lastLowWarn: 101
  onBatteryPercentChanged: {
    if (!settled || !hasBattery) return
    if (!onBattery) { lastLowWarn = 101; return }
    var levels = [20, 10, 5]
    for (var i = 0; i < levels.length; i++) {
      if (batteryPercent <= levels[i] && lastLowWarn > levels[i]) {
        lastLowWarn = levels[i]
        pushActivity({ kind: "alert", source: "power", icon: glyphs.batteryAlert, tint: "red", title: "Low Battery", value: batteryPercent + "%", duration: 4000 })
        break
      }
    }
  }

  // ------------------------------------------------------------ bluetooth
  Instantiator {
    model: Bluetooth.devices
    delegate: QtObject {
      required property var modelData
      readonly property bool connected: modelData ? !!modelData.connected : false
      onConnectedChanged: root.bluetoothChanged(modelData, connected)
    }
  }
  function bluetoothChanged(dev, connected) {
    if (!settled || !dev) return
    var icon = String(dev.icon || "")
    var audio = icon.indexOf("audio") !== -1 || icon.indexOf("headset") !== -1 || icon.indexOf("headphone") !== -1
    var level = dev.batteryAvailable ? Math.round((dev.battery <= 1 ? dev.battery * 100 : dev.battery)) + "%" : ""
    pushActivity({
      kind: "alert", source: "bluetooth",
      icon: audio ? glyphs.headphones : glyphs.bluetooth,
      tint: connected ? "blue" : "secondary",
      title: String(dev.name || dev.deviceName || "Bluetooth"),
      value: connected ? (level || "Connected") : "Disconnected",
      duration: 2600
    })
  }

  // ------------------------------------------------------------ do not disturb
  property bool dnd: false
  property bool dndLoaded: false
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/notifications.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var on = false
      try { on = !!JSON.parse(text() || "{}").doNotDisturb } catch (e) {}
      if (root.dndLoaded && root.settled && on !== root.dnd)
        root.pushActivity({ kind: "alert", source: "dnd", icon: on ? root.glyphs.moon : root.glyphs.bell, tint: on ? "indigo" : "secondary", title: "Do Not Disturb", value: on ? "On" : "Off", duration: 1800 })
      root.dnd = on
      root.dndLoaded = true
    }
  }

  // ------------------------------------------------------------ notifications
  // The Omarchy notification daemon persists each live popup as one JSON file
  // (removed/archived when the popup leaves). Watching that folder mirrors
  // new notifications into the island without a second D-Bus server.
  readonly property string notifDir: Quickshell.env("HOME") + "/.local/state/omarchy/notifications"
  property var seenNotifs: ({})
  property bool notifPrimed: false
  property string notifFile: ""

  FolderListModel {
    id: notifFolder
    folder: "file://" + root.notifDir
    nameFilters: ["*.json"]
    showDirs: false
    sortField: FolderListModel.Name
    sortReversed: true
    onStatusChanged: if (status === FolderListModel.Ready) root.scanNotifs()
    onCountChanged: root.scanNotifs()
  }
  function scanNotifs() {
    if (notifFolder.status !== FolderListModel.Ready) return
    var present = {}
    var fresh = ""
    for (var i = 0; i < notifFolder.count; i++) {
      var name = String(notifFolder.get(i, "fileName") || "")
      if (!name) continue
      present[name] = true
      if (!seenNotifs[name] && fresh === "") fresh = name
    }
    var next = {}
    for (var k in present) next[k] = true
    seenNotifs = next
    if (!notifPrimed) { notifPrimed = true; return }
    // A popup the user dismissed elsewhere shouldn't keep its island peek.
    if (activity && activity.kind === "notification" && !present[activity.file]) finishActivity()
    if (fresh !== "" && showNotifications) {
      notifFile = ""
      notifFile = root.notifDir + "/" + fresh
    }
  }
  FileView {
    id: notifReader
    path: root.notifFile
    printErrors: false
    onLoaded: {
      var d = null
      try { d = JSON.parse(text() || "{}") } catch (e) { return }
      var summary = Model.plainText(d.summary)
      var body = Model.plainText(d.body)
      if (summary === "" && body === "") return
      var sms = root.lastSms.body.slice(0, 24)
      if (sms !== "" && Date.now() - root.lastSms.time < 10000 && (body.indexOf(sms) !== -1 || summary.indexOf(sms) !== -1)) return
      var iconUrl = root.notifIcon(d, summary)
      var pn = root.phoneNotif(d)
      var file = root.notifFile.substring(root.notifFile.lastIndexOf("/") + 1)
      root.pushActivity({
        kind: "notification", source: "notification", file: file,
        app: root.notifApp(d, summary),
        title: pn ? String(pn.title) : (summary !== "" ? summary : body),
        body: pn ? root.newestLine(pn.text) : (summary !== "" ? body : ""), image: iconUrl,
        replyId: pn ? String(pn.replyId || "") : "",
        urgent: Number(d.urgency) === 2,
        duration: Number(d.urgency) === 2 ? 8000 : 5000
      })
    }
  }
  // Every phone notification arrives as "KDE Connect" with the KDE Connect logo;
  // the Android app's own name is in the summary. Taildroid keeps that name
  // pointed at the icon KDE Connect fetched from the phone, so WhatsApp looks
  // like WhatsApp here, the same as it does on the phone.
  readonly property string phoneRelay: "KDE Connect"
  // The relayed notification only carries "<title>: <text>" as one escaped line.
  // Taildroid publishes what the phone itself shows, so match this one to it and
  // take the chat's own icon, its title, and its newest line.
  function phoneNotif(d) {
    if (String(d.app || "") !== phoneRelay || !root.phone) return null
    var app = Model.plainText(d.summary)
    var body = Model.plainText(d.body)
    var list = root.phone.pstate.phoneNotifs || []
    var fallback = null
    for (var i = 0; i < list.length; i++) {
      if (String(list[i].app) !== app) continue
      if (body.indexOf(String(list[i].title)) === 0) return list[i]
      if (!fallback) fallback = list[i]
    }
    return fallback
  }
  // WhatsApp stacks a chat's messages oldest first, one per <br/>. The newest is
  // the last of those, and a single message may itself run over several lines.
  function newestLine(text) {
    var parts = String(text || "").split(/<br\s*\/?>/i)
    for (var i = parts.length - 1; i >= 0; i--) {
      var one = Model.plainText(parts[i]).replace(/\s+/g, " ").trim()
      if (one !== "") return one
    }
    return ""
  }
  function notifApp(d, summary) {
    var app = String(d.app || "")
    return app === phoneRelay && String(summary || "") !== "" ? String(summary) : app
  }
  function notifIcon(d, summary) {
    if (String(d.app || "") === phoneRelay && root.phone) {
      var pn = root.phoneNotif(d)
      var chats = root.phone.pstate.phoneChats || {}
      var icon = pn && String(pn.icon || "") !== "" ? String(pn.icon)
        : String(chats[String(summary || "") + "\u0000" + Model.plainText(d.body).split(":")[0]]
                 || (root.phone.pstate.phoneApps || {})[String(summary || "")] || "")
      if (icon !== "") return icon.indexOf("/") === 0 ? "file://" + icon : icon
    }
    var image = String(d.image || "")
    if (image !== "") return image
    var appIcon = String(d.appIcon || "")
    if (appIcon.indexOf("/") !== -1 || appIcon.indexOf("file:") === 0) return appIcon
    if (appIcon !== "") return Quickshell.iconPath(appIcon, true)
    return root.appIconFor(notifApp(d, summary))
  }

  // No reply handle (Gmail, GPay…): the next best thing is that app on this
  // machine — most of them are Omarchy webapps, which open on the right service.
  function openForApp(app) {
    var name = String(app || "").trim()
    if (name === "") return false
    var entry = typeof DesktopEntries.heuristicLookup === "function" ? DesktopEntries.heuristicLookup(name) : null
    if (!entry) return false
    if (typeof entry.execute === "function") { entry.execute(); return true }
    return false
  }

  // Many apps send no icon at all; fall back to the app's own desktop-entry
  // icon (Firefox, Spotify…) so notifications carry the app's logo, not a bell.
  function appIconFor(app) {
    var name = String(app || "").trim()
    if (name === "") return ""
    var entry = typeof DesktopEntries.heuristicLookup === "function" ? DesktopEntries.heuristicLookup(name) : null
    if (entry && entry.icon) return Quickshell.iconPath(entry.icon, true)
    return Quickshell.iconPath(name.toLowerCase().replace(/\s+/g, "-"), true)
  }

  // SMS arrive twice (phoned + KDE Connect's mirrored popup); keep ours.
  property var lastSms: ({ body: "", time: 0 })
  property var pendingThread: null
  // A chat you can answer opens its reply box; anything else opens the app it
  // came from, so clicking a notification always lands somewhere useful.
  property var replyTarget: null
  function notificationActivate() {
    if (activity && activity.sms) {
      controlsRequested("messages")
      pendingThread = activity.sms
      finishActivity()
      return
    }
    if (activity && String(activity.replyId || "") !== "") {
      replyTarget = { replyId: String(activity.replyId), title: String(activity.title || ""), file: String(activity.file || "") }
      controlsRequested("notifications")
      finishActivity()
      return
    }
    if (activity && root.openForApp(activity.app)) {
      finishActivity()
      return
    }
    Quickshell.execDetached(["omarchy-shell", "-q", "notifications", "invokeLast"])
    finishActivity()
  }
  function notificationDismiss() {
    Quickshell.execDetached(["omarchy-shell", "-q", "notifications", "dismissOne"])
    finishActivity()
  }

  // ------------------------------------------------------------ transients
  // One activity shows at a time. A repeat of the same source (holding the
  // volume key) updates in place; HUDs and alerts cut in front of queued
  // notifications, and anything else waits its turn.
  property var activity: null
  property var queue: []
  property int activitySerial: 0

  function pushActivity(t) {
    if (!t) return
    if (activity && activity.source === t.source && t.kind === activity.kind) {
      activity = t
      activityTimer.interval = t.duration
      activityTimer.restart()
      return
    }
    if (!activity) { showActivity(t); return }
    var quick = t.kind === "hud" || t.kind === "alert"
    if (quick && activity.kind !== "notification") {
      // A key press answers the last one: swap in place, no queueing.
      showActivity(t)
      return
    }
    if (quick) {
      queue = [activity].concat(queue)
      showActivity(t)
      return
    }
    var q = queue.slice()
    for (var i = 0; i < q.length; i++) {
      if (q[i].source === t.source && q[i].kind === t.kind) { q[i] = t; queue = q; return }
    }
    q.push(t)
    queue = q.slice(-6)
  }
  function showActivity(t) {
    activity = t
    activitySerial++
    activityTimer.interval = t.duration
    activityTimer.restart()
  }
  function finishActivity() {
    activityTimer.stop()
    if (queue.length > 0) {
      var q = queue.slice()
      var next = q.shift()
      queue = q
      // Let the island settle for a beat between two activities, so each
      // one reads as its own event instead of a jump cut.
      activity = null
      nextActivityTimer.pending = next
      nextActivityTimer.restart()
    } else {
      activity = null
    }
  }
  function holdActivity(hold) {
    if (!activity) return
    if (hold) activityTimer.stop()
    else { activityTimer.interval = 1500; activityTimer.restart() }
  }
  Timer {
    id: activityTimer
    onTriggered: root.finishActivity()
  }
  Timer {
    id: nextActivityTimer
    property var pending: null
    interval: 260
    onTriggered: if (pending) { root.showActivity(pending); pending = null }
  }

  // ------------------------------------------------------------ live activity
  // Every live activity at once, most important first. The first one owns
  // the island; the second sits beside it as a detached bubble (iOS's
  // "minimal" presentation when two activities run together).
  readonly property var lives: {
    var out = []
    if (currentCall) out.push("call")
    if (recording) out.push("recording")
    if (phoneMirroring) out.push("phone")
    if (timerActive) out.push("timer")
    if (mediaLive) out.push("media")
    return out
  }
  readonly property string live: lives.length > 0 ? lives[0] : ""
  readonly property string secondLive: lives.length > 1 ? lives[1] : ""

  // ------------------------------------------------------------ volume by scroll
  function scrollVolumeBy(delta) {
    if (!root.scrollVolume) return
    Quickshell.execDetached(["omarchy-audio-output-volume", delta > 0 ? "+2" : "-2"])
  }

  // ------------------------------------------------------------ earbuds
  // OnePlus Experience's own service, loaded from its plugin folder when it's
  // installed, so the Control Center drives the buds through the same code
  // path as that plugin's panel.
  readonly property string budsServicePath: Quickshell.env("HOME") + "/.config/omarchy/plugins/io.github.buildscript-dev.oneplus-experience/Service.qml"
  FileView { id: budsProbe; path: root.budsServicePath; printErrors: false }
  Loader {
    id: budsLoader
    active: budsProbe.loaded
    source: active ? "file://" + root.budsServicePath : ""
  }
  readonly property var buds: budsLoader.item
  readonly property bool budsConnected: !!(buds && buds.status && buds.status.connected)
  readonly property string budsName: buds && buds.status && buds.status.deviceName ? buds.status.deviceName : "Earbuds"
  readonly property var budsModeNames: ({ anc: "Noise Cancellation", smart: "Smart ANC", transparency: "Transparency", off: "Noise Control Off" })
  readonly property var budsModeGlyphs: ({ anc: "󰟎", smart: "󰧑", transparency: "󰈈", off: "󰋋" })
  function budsPart(p) { return p && p.level >= 0 ? p.level + "%" : "–" }
  // AirPods-style: a pill with both buds' battery when they connect, and a
  // quick confirmation when the noise mode changes (from here, the buds or the phone).
  onBudsConnectedChanged: {
    if (!settled || !budsConnected) return
    var st = buds.status
    pushActivity({ kind: "alert", source: "buds", icon: "󱡏", tint: "white", title: budsName,
      value: "L " + budsPart(st.left) + "  R " + budsPart(st.right), duration: 3200 })
  }
  property string lastBudsMode: ""
  Connections {
    target: root.buds
    ignoreUnknownSignals: true
    function onStatusChanged() {
      var st = root.buds.status
      var mode = st && st.linked ? String(st.noiseMode || "") : ""
      if (root.settled && mode !== "" && root.lastBudsMode !== "" && mode !== root.lastBudsMode)
        root.pushActivity({ kind: "alert", source: "buds-mode", icon: root.budsModeGlyphs[mode] || "󰋋", tint: mode === "off" ? "secondary" : "blue",
          title: root.budsModeNames[mode] || mode, value: "", duration: 1800 })
      if (mode !== "") root.lastBudsMode = mode
    }
  }

  // ------------------------------------------------------------ phone (Taildroid)
  // Taildroid's own service, so mirroring works with its bar widget removed.
  readonly property string phoneServicePath: Quickshell.env("HOME") + "/.config/omarchy/plugins/io.github.buildscript-dev.taildroid/Service.qml"
  FileView { id: phoneProbe; path: root.phoneServicePath; printErrors: false }
  Loader {
    id: phoneLoader
    active: phoneProbe.loaded
    source: active ? "file://" + root.phoneServicePath : ""
    onLoaded: item.refresh()
  }
  readonly property var phone: phoneLoader.item
  readonly property bool phoneMirroring: !!(phone && phone.sessionRunning)
  property real phoneSince: 0
  onPhoneMirroringChanged: if (phoneMirroring) phoneSince = Date.now()

  // Calls ride the phone's Bluetooth hands-free link (PipeWire telephony):
  // a ringing call takes over the island, an ongoing one is a live activity.
  readonly property var phoneCalls: phone && phone.calls ? phone.calls : []
  readonly property var ringingCall: {
    for (var i = 0; i < phoneCalls.length; i++)
      if (phoneCalls[i].state === "incoming" || phoneCalls[i].state === "waiting") return phoneCalls[i]
    return null
  }
  readonly property var currentCall: {
    for (var i = 0; i < phoneCalls.length; i++)
      if (phoneCalls[i].state !== "incoming" && phoneCalls[i].state !== "disconnected") return phoneCalls[i]
    return null
  }
  function callTitle(c) { return c ? (c.name || c.number || "Unknown") : "" }
  function callElapsed(c) {
    root.now
    if (!c) return ""
    if (c.state === "dialing" || c.state === "alerting") return "Calling…"
    if (c.state === "held") return "On Hold"
    return c.activeSince > 0 ? Model.formatTime(Date.now() / 1000 - c.activeSince) : ""
  }
  readonly property string phoneName: phone && phone.pstate && phone.pstate.phone && phone.pstate.phone.model ? phone.pstate.phone.model : "Galaxy S24"
  Connections {
    target: root.phone
    ignoreUnknownSignals: true
    function onPhoneEvent(ev) {
      if (!root.settled) return
      if (ev.kind === "connected")
        root.pushActivity({ kind: "alert", source: "phone-link", icon: "󰄜", tint: "green", title: ev.model || root.phoneName,
          value: ev.transport === "usb" ? "USB" : "Wi-Fi", duration: 2400 })
      else if (ev.kind === "disconnected")
        root.pushActivity({ kind: "alert", source: "phone-link", icon: "󰥐", tint: "secondary", title: root.phoneName, value: "Disconnected", duration: 2000 })
      else if (ev.kind === "callEnded")
        root.pushActivity({ kind: "alert", source: "call", icon: "󰏷", tint: "red", title: root.callTitle(ev),
          value: ev.activeSince > 0 ? Model.formatTime(Date.now() / 1000 - ev.activeSince) : "Call Ended", duration: 2600 })
      else if (ev.kind === "missedCall")
        root.pushActivity({ kind: "alert", source: "call", icon: "󰵋", tint: "red", title: ev.name || ev.number || "Unknown", value: "Missed Call", duration: 5000 })
      else if (ev.kind === "nearby") {
        var b = root.phone.pstate && root.phone.pstate.battery ? root.phone.pstate.battery.level : -1
        root.pushActivity({ kind: "alert", source: "phone-link", icon: "󰄜", tint: "blue", title: ev.name || root.phoneName,
          value: b >= 0 ? b + "%" : "Nearby", duration: 2400 })
      }
      else if (ev.kind === "hotspot")
        root.pushActivity({ kind: "alert", source: "hotspot", icon: "󰀂", tint: ev.on ? "green" : "secondary", title: "Hotspot",
          value: ev.on ? "Connected" : "Off", duration: 2200 })
      else if (ev.kind === "sms") {
        root.lastSms = { body: String(ev.body || ""), time: Date.now() }
        if (root.showNotifications)
          root.pushActivity({ kind: "notification", source: "sms", file: "", app: "Messages · " + root.phoneName,
            title: ev.name || (ev.addresses || []).join(", "), body: String(ev.body || ""), image: "",
            urgent: false, duration: 6000, sms: ev })
      }
      else if (ev.kind === "error")
        root.pushActivity({ kind: "alert", source: "phone-error", icon: "󰀦", tint: "orange", title: String(ev.message || "Phone").slice(0, 60), value: "", duration: 3500 })
    }
  }

  // ------------------------------------------------------------ system update
  property bool updateAvailable: false
  Process {
    id: updateCheck
    command: ["omarchy-update-available"]
    onExited: function(code) { root.updateAvailable = code === 0 }
  }
  Timer { interval: 21600000; running: root.onlineExtras; repeat: true; triggeredOnStart: true; onTriggered: updateCheck.running = true }
  function checkUpdates() { if (root.onlineExtras && !updateCheck.running) updateCheck.running = true }
  function runUpdate() { Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", "omarchy-update"]) }

  // ------------------------------------------------------------ keyboard layout
  // The bar's layout widget is gone, so the island announces layout switches.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || String(event.name) !== "activelayout" || !root.settled) return
      var data = String(event.data || "")
      var layout = data.substring(data.lastIndexOf(",") + 1)
      if (layout === "" || layout === root.lastLayout) return
      // The first report is the current layout, not a switch.
      var first = root.lastLayout === ""
      root.lastLayout = layout
      if (first) return
      root.pushActivity({ kind: "alert", source: "layout", icon: root.glyphs.keyboard, tint: "white", title: layout, value: "", duration: 1600 })
    }
  }
  property string lastLayout: ""

  // ------------------------------------------------------------ workspaces
  // The bar is gone, so switching workspaces flashes a pill with a dot per
  // workspace and the active one filled.
  property int lastWorkspace: -1
  property string lastWorkspaceMonitor: ""
  readonly property var activeWorkspace: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.activeWorkspace : null
  onActiveWorkspaceChanged: {
    var ws = activeWorkspace
    if (!ws || ws.id <= 0) return
    var mon = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name) : ""
    // Moving focus to another monitor isn't a switch; only a new workspace on the same monitor is.
    var sameMonitor = mon === lastWorkspaceMonitor
    lastWorkspaceMonitor = mon
    if (settled && showWorkspaces && sameMonitor && lastWorkspace !== -1 && ws.id !== lastWorkspace) {
      var ids = []
      var list = Hyprland.workspaces ? Hyprland.workspaces.values : []
      for (var i = 0; i < list.length; i++) if (list[i] && list[i].id > 0 && ids.indexOf(list[i].id) === -1) ids.push(list[i].id)
      if (ids.indexOf(ws.id) === -1) ids.push(ws.id)
      ids.sort(function(a, b) { return a - b })
      var dots = ids.map(function(id) { return id === ws.id ? "●" : "○" }).join(" ")
      pushActivity({ kind: "alert", source: "workspace", icon: "󰍹", tint: "white", title: String(ws.name || ws.id), value: dots, duration: 1100 })
    }
    lastWorkspace = ws.id
  }

  // ------------------------------------------------------------ weather
  property string weatherText: ""
  property string weatherPlace: ""
  property string weatherTemp: ""
  Process {
    id: weatherRead
    command: ["omarchy-weather-status"]
    stdout: StdioCollector {
      onStreamFinished: {
        var t = String(text || "").trim()
        if (t === "" || t.indexOf("unavailable") !== -1) return
        var parts = t.split("·").map(function(x) { return x.trim() })
        root.weatherPlace = parts[0] || ""
        root.weatherTemp = (parts[1] || "").replace(/^Temp\s*/, "")
        root.weatherText = root.weatherPlace + (root.weatherTemp ? " · " + root.weatherTemp : "")
      }
    }
  }
  Timer { interval: 1800000; running: root.onlineExtras; repeat: true; triggeredOnStart: true; onTriggered: if (!weatherRead.running) weatherRead.running = true }
  onOnlineExtrasChanged: if (!onlineExtras) { weatherText = ""; weatherPlace = ""; weatherTemp = ""; updateAvailable = false }

  // ------------------------------------------------------------ notification history
  readonly property string historyDir: root.notifDir + "/history"
  property var history: []
  FolderListModel {
    id: historyFolder
    folder: "file://" + root.historyDir
    nameFilters: ["*.json"]
    showDirs: false
    onCountChanged: root.readHistory()
    onStatusChanged: if (status === FolderListModel.Ready) root.readHistory()
  }
  function readHistory() {
    if (historyRead.running) { historyAgain = true; return }
    historyRead.running = true
  }
  property bool historyAgain: false
  Process {
    id: historyRead
    command: ["bash", "-c", "for f in \"$1\"/*.json; do [ -e \"$f\" ] || continue; printf '%s\\t' \"${f##*/}\"; tr -d '\\n' < \"$f\"; echo; done", "--", root.historyDir]
    stdout: StdioCollector {
      onStreamFinished: {
        var out = []
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var tab = lines[i].indexOf("\t")
          if (tab < 0) continue
          try {
            var d = JSON.parse(lines[i].substring(tab + 1))
            var summary = Model.plainText(d.summary)
            var pn = root.phoneNotif(d)
            out.push({ file: lines[i].substring(0, tab), app: root.notifApp(d, summary),
              title: pn ? String(pn.title) : summary,
              body: pn ? root.newestLine(pn.text) : Model.plainText(d.body),
              time: Number(d.timestamp) || 0, urgent: Number(d.urgency) === 2,
              replyId: pn ? String(pn.replyId || "") : "",
              image: root.notifIcon(d, summary) })
          } catch (e) {}
        }
        out.sort(function(a, b) { return b.time - a.time })
        root.history = out
      }
    }
    onExited: if (root.historyAgain) { root.historyAgain = false; root.readHistory() }
  }
  function clearHistory() {
    Quickshell.execDetached(["omarchy-shell", "-q", "notifications", "clear"])
    history = []
  }
  function removeHistory(file) {
    if (!/^[A-Za-z0-9._-]+\.json$/.test(file)) return
    Quickshell.execDetached(["bash", "-c", "rm -f \"$1/$3\" \"$2/${3%.json}\"-*", "--", root.historyDir, root.notifDir + "/images", file])
    history = history.filter(function(n) { return n.file !== file })
  }
  function timeAgo(ms) {
    var d = Math.max(0, (root.now.getTime() - ms) / 1000)
    if (d < 60) return "now"
    if (d < 3600) return Math.floor(d / 60) + "m"
    if (d < 86400) return Math.floor(d / 3600) + "h"
    return Math.floor(d / 86400) + "d"
  }

  // ------------------------------------------------------------ clock
  // The bar clock moved into the island; this is the one place time is formatted.
  readonly property string clockFormat: String(setting("clockFormat", "HH:mm"))
  readonly property string clockText: Qt.formatDateTime(root.now, root.clockFormat)
  readonly property bool showClock: setting("showClock", true) === true

  // ------------------------------------------------------------ control center
  signal controlsRequested(string page)
  property bool controlsShown: false

  // ------------------------------------------------------------ expanded (shared across windows)
  // Only the most recent screen to open wins; another screen opening closes it.
  property var expandedWindow: null
  signal collapseAll()

  // ------------------------------------------------------------ bar footprint
  // The bar spacer reads this so bar widgets flow around the notch the way
  // the macOS menu bar flows around the camera housing.
  // The window on the focused screen reports its resting width here.
  property int restingWidth: notchWidth
  readonly property int barFootprint: restingWidth + (secondLive !== "" ? notchHeight + 8 : 0) * 2

  // ------------------------------------------------------------ IPC
  IpcHandler {
    // Taking over the `osd` target routes every `omarchy osd` call (volume,
    // brightness, keyboard light, mic, media keys) into the island — the
    // stock OSD plugin must be disabled for this (see README).
    target: root.replaceOsd ? "osd" : "dynamic-island-osd"
    function show(payloadJson: string): string {
      var p = {}
      try { p = JSON.parse(payloadJson || "{}") } catch (e) { return "bad-json" }
      root.pushActivity(Model.osdTransient(p))
      return "ok"
    }
    function close(): string {
      if (root.activity && (root.activity.kind === "hud" || root.activity.kind === "alert")) root.finishActivity()
      return "ok"
    }
    function state(): string { return root.activity ? "open" : "closed" }
    function ping(): string { return "ok" }
  }

  IpcHandler {
    target: "island"
    function state(): string {
      return JSON.stringify({
        live: root.live, second: root.secondLive, controls: root.controlsShown, activity: root.activity, queued: root.queue.length,
        media: { title: root.trackTitle, artist: root.trackArtist, playing: root.isPlaying, player: root.playerName },
        timerLeft: Math.round(root.timerLeft), recording: root.recording, micInUse: root.micInUse,
        battery: root.batteryPercent, charging: root.charging, dnd: root.dnd,
        shape: root.shape, monitor: root.monitor, style: root.style, palette: root.palette, font: root.textFont, notchHeight: root.notchHeight
      })
    }
    function ping(): string { return "ok" }
    function expand(): string { root.expandRequested(); return "ok" }
    // Open the Control Center, optionally on a page: wifi, bluetooth, audio,
    // buds, phone, notifications, calendar, power.
    function controls(page: string): string { root.controlsRequested(page || "main"); return "ok" }
    // Taildroid mirroring on/off (Super+Shift+I).
    function phoneToggle(): string { if (!root.phone) return "no-taildroid"; root.phone.toggleControl(); return "ok" }
    function collapse(): string { root.collapseAll(); return "ok" }
    // Phone continuity: answer/decline from the keyboard, dial, open messages.
    function answer(): string { if (!root.phone) return "no-taildroid"; root.phone.answer(""); return "ok" }
    function hangup(): string { if (!root.phone) return "no-taildroid"; root.phone.hangup(""); return "ok" }
    function dial(number: string): string { if (!root.phone) return "no-taildroid"; root.phone.dial(number); return "ok" }
    function messages(): string { root.controlsRequested("messages"); return "ok" }
    function phoneDex(): string { if (!root.phone) return "no-taildroid"; root.phone.openDex(); return "ok" }
    function timer(seconds: string): string { root.startTimer(Number(seconds)); return "ok" }
    function timerCancel(): string { root.cancelTimer(); return "ok" }
    function alert(icon: string, title: string, value: string): string {
      root.pushActivity({ kind: "alert", source: "ipc-" + title, icon: icon, tint: "white", title: title, value: value, duration: 2500 })
      return "ok"
    }
    function hud(icon: string, percent: string): string {
      root.pushActivity(Model.osdTransient({ icon: icon, value: percent }))
      return "ok"
    }
    function notify(title: string, body: string): string {
      root.pushActivity({ kind: "notification", source: "ipc-notify", file: "", app: "Dynamic Island", title: title, body: body, image: "", urgent: false, duration: 5000 })
      return "ok"
    }
  }
  signal expandRequested()

  // ------------------------------------------------------------ windows
  Variants {
    model: {
      var all = Quickshell.screens
      if (root.monitor === "all" || root.monitor === "focused" || root.monitor === "") return all
      var out = []
      for (var i = 0; i < all.length; i++) if (all[i].name === root.monitor) out.push(all[i])
      return out.length > 0 ? out : all
    }
    delegate: IslandWindow {
      required property var modelData
      screen: modelData
      screenName: modelData ? String(modelData.name) : ""
      service: root
    }
  }
}
