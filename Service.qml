import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Wayland
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

  // ------------------------------------------------------------ processes
  // Fire-and-forget actions and long-lived launches, both in the closed
  // environment with fixed executables (IslandModel.js). Readers use SafeProcess.
  readonly property var childEnv: Model.childEnv(function(k) { return Quickshell.env(k) })
  function fire(argv, seconds) {
    Quickshell.execDetached({ command: Model.bounded(argv, seconds || 20, 0), environment: root.childEnv, clearEnvironment: true })
  }
  // Only for programs meant to outlive a deadline: the update terminal, a
  // screen recording, a locker, a file the user opened.
  function launch(argv) {
    Quickshell.execDetached({ command: Model.direct(argv), environment: root.childEnv, clearEnvironment: true })
  }
  // A regular file (not a link, FIFO or device) printed to stdout; the caller
  // caps the size. A path swapped for a FIFO after the check blocks until the
  // deadline kills it.
  readonly property string readFile: "[ -f \"$1\" ] && [ ! -L \"$1\" ] && exec /usr/bin/cat -- \"$1\""

  // ------------------------------------------------------------ settings
  // Settings live on the island's bar entry in shell.json, like every other
  // bar widget, so the Omarchy settings UI and `updateEntryInline` apply.
  // The shell's public barConfig snapshot only refreshes on plugin-registry
  // events, so the island reads shell.json itself to apply edits instantly.
  property var liveBarConfig: null
  readonly property string shellConfigPath: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
  // The FileViews in this plugin only watch (preload: false); the bytes are
  // read by a bounded helper that refuses anything but a regular file.
  FileView {
    path: root.shellConfigPath
    preload: false
    watchChanges: true
    printErrors: false
    onFileChanged: configRead.running = true
  }
  SafeProcess {
    id: configRead
    running: true
    command: Model.bounded(["bash", "-c", root.readFile, "read", root.shellConfigPath], 3, 1048576)
    stdout: StdioCollector {
      onStreamFinished: {
        var t = Model.capped(text, 1048576)
        if (t === null || t === "") return
        try {
          var parsed = JSON.parse(t)
          root.liveBarConfig = parsed && parsed.bar ? parsed.bar : null
        } catch (e) {}
      }
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
  readonly property string paletteName: String(setting("palette", "apple"))   // apple | theme (QQuickItem already owns "palette")
  // pill: a floating iPhone-style bubble inside the bar · notch: a MacBook
  // notch hanging from the top edge.
  readonly property string shape: String(setting("shape", "pill"))
  readonly property bool pill: shape !== "notch"
  readonly property int notchWidth: pill ? Number(setting("islandWidth", 96)) : Number(setting("notchWidth", 200))
  readonly property bool openOnHover: setting("openOnHover", true) === true
  readonly property int hoverDelay: Number(setting("hoverDelay", 320))
  readonly property bool showNotifications: setting("showNotifications", true) === true
  // The phone's own screen is on this desktop while it is mirrored, and it
  // shows its notifications, its messages and its status itself. The island
  // stays out of the way until the mirror closes.
  readonly property bool muteWhileMirrored: setting("muteWhileMirrored", true) === true
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
  readonly property bool showCameraIndicator: setting("showCameraIndicator", true) === true
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
    if (paletteName === "theme") {
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

  // Live spectrum from cava while music plays; [] means the waveform animates
  // on its own (cava missing, or it keeps dying).
  property var spectrum: []
  property int cavaFails: 0
  function syncCava() {
    var want = isPlaying && cavaFails < 3
    if (want !== cava.running) cava.running = want
  }
  SafeProcess {
    id: cava
    command: Model.direct(["cava", "-p", decodeURIComponent(Qt.resolvedUrl("cava.conf").toString().replace("file://", ""))])
    stdout: SplitParser {
      onRead: function(line) {
        var v = Model.parseSpectrum(line, 6)
        if (v) { root.spectrum = v; root.cavaFails = 0 }
      }
    }
    onRunningChanged: if (!running) {
      root.spectrum = []
      if (root.isPlaying) { root.cavaFails++; cavaRetry.restart() }
    }
  }
  Timer { id: cavaRetry; interval: 3000; onTriggered: root.syncCava() }
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
    syncCava()
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

  // Album art never goes straight into an Image: the shell would fetch or
  // decode whatever the player named. It is copied into a private directory
  // first — /run/user/<uid> is root-created, per-user and 0700, and the island
  // keeps exactly one image there — and only that copy is drawn and tinted.
  // Remote art (Spotify and other streamers) is downloaded under the
  // onlineExtras switch; local art (browsers, mpv) is copied the same way.
  // Either way the file is capped at 4 MB by the kernel while it is written
  // (ulimit -f, 512-byte blocks; XFSZ ignored so the write fails with EFBIG
  // instead of dumping core), and the whole job has a 15 s deadline.
  readonly property int artMaxBytes: 4194304
  readonly property string artScript:
    "d=\"/run/user/$UID/omarchy-dynamic-island\"; umask 077; " +
    "/usr/bin/mkdir -p -m 700 -- \"$d\" 2>/dev/null; " +
    "[ -d \"$d\" ] && [ ! -L \"$d\" ] && [ -O \"$d\" ] && [ \"$(/usr/bin/stat -c %a -- \"$d\")\" = 700 ] || exit 1; " +
    "t=$(/usr/bin/mktemp -- \"$d/art.XXXXXX\") || exit 1; trap '/usr/bin/rm -f -- \"$t\"' EXIT; " +
    "if [ \"$2\" = url ]; then " +
    "( trap '' XFSZ; ulimit -f " + (root.artMaxBytes / 512) + " && exec /usr/bin/curl -q -fsL " +
    "--proto =http,https --proto-redir =http,https --max-redirs 3 --max-time 10 " +
    "--max-filesize " + root.artMaxBytes + " -o \"$t\" -- \"$1\" ) || exit 1; " +
    "else [ -f \"$1\" ] && [ ! -L \"$1\" ] || exit 1; " +
    "( trap '' XFSZ; ulimit -f " + (root.artMaxBytes / 512) + " && exec /usr/bin/head -c " + (root.artMaxBytes + 1) + " -- \"$1\" > \"$t\" ) || exit 1; fi; " +
    "[ -s \"$t\" ] && [ \"$(/usr/bin/stat -c %s -- \"$t\")\" -le " + root.artMaxBytes + " ] || exit 1; " +
    // A new name per track, so the Image and the quantizer see a new URL.
    "f=\"$d/$(printf %s \"$1\" | /usr/bin/md5sum | /usr/bin/cut -c1-20).img\"; " +
    "/usr/bin/mv -f -- \"$t\" \"$f\" || exit 1; " +
    "/usr/bin/find \"$d\" -maxdepth 1 -type f ! -name \"${f##*/}\" -delete; printf %s \"$f\""
  property string artLocal: ""
  onTrackArtChanged: fetchArt()
  Component.onCompleted: fetchArt()
  function fetchArt() {
    artLocal = ""
    artFetch.running = false
    if (trackArt === "") return
    var remote = /^https?:\/\//i.test(trackArt)
    var arg = ""
    if (remote) {
      // Remote artwork is the only download the island itself makes.
      if (!onlineExtras || trackArt.length > 2048) return
      arg = trackArt
    } else {
      var local = Model.localImage(trackArt)
      if (local.indexOf("file://") !== 0) return
      try { arg = decodeURIComponent(local.slice(7)) } catch (e) { return }
    }
    artFetch.command = Model.bounded(["bash", "-c", root.artScript, "art", arg, remote ? "url" : "file"], 15, 4096)
    artFetch.running = true
  }
  SafeProcess {
    id: artFetch
    stdout: StdioCollector {
      onStreamFinished: {
        var p = String(Model.capped(text, 4096) || "").trim()
        if (/^\/run\/user\/[0-9]+\/omarchy-dynamic-island\/[0-9a-f]{20}\.img$/.test(p)) root.artLocal = "file://" + p
      }
    }
  }

  ColorQuantizer {
    id: artQuantizer
    source: root.artworkTint ? root.artLocal : ""
    depth: 2
    rescaleSize: 48
  }
  readonly property color mediaAccent: artworkTint && trackArt !== ""
    ? Model.vividColor(artQuantizer.colors, tint("white"))
    : (paletteName === "theme" ? Color.accent : tint("white"))

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
        root.fire(["pw-play", "/usr/share/sounds/freedesktop/stereo/complete.oga"], 10)
      }
    }
  }

  // ------------------------------------------------------------ stopwatch
  property real stopwatchSince: 0   // epoch ms the running count started from; 0 = stopped
  property real stopwatchHeld: -1   // seconds shown while paused
  readonly property bool stopwatchActive: stopwatchSince > 0 || stopwatchHeld >= 0
  readonly property real stopwatchElapsed: {
    root.now
    if (stopwatchHeld >= 0) return stopwatchHeld
    return stopwatchSince > 0 ? (Date.now() - stopwatchSince) / 1000 : 0
  }
  function toggleStopwatch() {
    if (stopwatchHeld >= 0) { stopwatchSince = Date.now() - stopwatchHeld * 1000; stopwatchHeld = -1 }
    else if (stopwatchSince > 0) { stopwatchHeld = (Date.now() - stopwatchSince) / 1000; stopwatchSince = 0 }
    else stopwatchSince = Date.now()
  }
  function resetStopwatch() { stopwatchSince = 0; stopwatchHeld = -1 }

  // ------------------------------------------------------------ alarm
  // ponytail: one alarm, kept in memory only; a shell restart forgets it. Persist it if people rely on it to wake up.
  property real alarmAt: 0          // epoch ms; 0 = none
  function setAlarm(hhmm) {
    var at = Model.nextAlarm(hhmm, Date.now())
    if (!at) return false
    alarmAt = at
    pushActivity({ kind: "alert", source: "alarm", icon: glyphs.alarm, tint: "orange", title: "Alarm", value: Model.clockText(at), duration: 1600 })
    return true
  }
  function cancelAlarm() { alarmAt = 0 }
  Timer {
    interval: 1000
    repeat: true
    running: root.alarmAt > 0
    onTriggered: {
      if (Date.now() < root.alarmAt) return
      var at = root.alarmAt
      root.alarmAt = 0
      root.pushActivity({ kind: "alert", source: "alarm-done", icon: root.glyphs.alarm, tint: "orange", title: "Alarm", value: Model.clockText(at), duration: 10000 })
      root.fire(["pw-play", "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"], 15)
    }
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
  SafeProcess {
    id: recProc
    command: Model.bounded(["pgrep", "--quiet", "-f", "^gpu-screen-recorder"], 5, 0)
    onExited: function(code) {
      var on = code === 0
      if (on && !root.recording) root.recordingSince = Date.now()
      root.recording = on
    }
  }
  function stopRecording() {
    root.fire(["omarchy-capture-screenrecording", "--stop-recording"], 30)
  }

  // ------------------------------------------------------------ privacy dots
  // One poll answers for both. PipeWire only sees a camera that came through
  // the portal, and most apps open /dev/video* themselves, so ask the kernel
  // who holds the device. Capture off a monitor source is desktop audio, not
  // the microphone, so those streams are skipped.
  property bool micInUse: false
  property bool cameraInUse: false
  Timer {
    interval: 2500
    repeat: true
    running: root.showMicIndicator || root.showCameraIndicator
    triggeredOnStart: true
    onTriggered: if (!privacyProc.running) privacyProc.running = true
  }
  SafeProcess {
    id: privacyProc
    command: Model.bounded(["bash", "-c", "c=0; m=0; /usr/bin/fuser -s /dev/video* 2>/dev/null && c=1; mons=\" $(/usr/bin/pactl list sources short | /usr/bin/grep '\\.monitor' | /usr/bin/cut -f1 | /usr/bin/tr '\\n' ' ')\"; for id in $(/usr/bin/pactl list source-outputs 2>/dev/null | /usr/bin/sed -n 's/^\\tSource: //p'); do case \"$mons\" in *\" $id \"*) ;; *) m=1 ;; esac; done; echo \"$m$c\""], 5, 16)
    stdout: StdioCollector {
      onStreamFinished: {
        var t = String(Model.capped(text, 16) || "").trim()
        root.micInUse = root.showMicIndicator && t.charAt(0) === "1"
        root.cameraInUse = root.showCameraIndicator && t.charAt(1) === "1"
      }
    }
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
  // Omarchy's notification service owns the switch; ask it. Its settings file
  // is only watched, as the cue that something else flipped it.
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/notifications.json"
    preload: false
    watchChanges: true
    printErrors: false
    onFileChanged: root.readDnd()
  }
  // The file only exists after the first toggle, so a slow poll covers what a
  // watch on a missing path can't see.
  Timer { interval: 20000; repeat: true; running: true; triggeredOnStart: true; onTriggered: root.readDnd() }
  Timer { id: dndLater; interval: 400; onTriggered: root.readDnd() }
  function readDnd() { if (!dndRead.running) dndRead.running = true }
  function toggleDnd() {
    root.fire(["omarchy-shell", "-q", "notifications", "toggleDnd"], 10)
    dndLater.restart()
  }
  SafeProcess {
    id: dndRead
    command: Model.bounded(["omarchy-shell", "notifications", "dndState"], 5, 16)
    stdout: StdioCollector {
      onStreamFinished: {
        var t = String(Model.capped(text, 16) || "").trim()
        if (t !== "on" && t !== "off") return
        var on = t === "on"
        if (root.dndLoaded && root.settled && on !== root.dnd)
          root.pushActivity({ kind: "alert", source: "dnd", icon: on ? root.glyphs.moon : root.glyphs.bell, tint: on ? "indigo" : "secondary", title: "Do Not Disturb", value: on ? "On" : "Off", duration: 1800 })
        root.dnd = on
        root.dndLoaded = true
      }
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
    if (fresh !== "" && showNotifications && /^[A-Za-z0-9._-]+\.json$/.test(fresh)) {
      notifFile = root.notifDir + "/" + fresh
      notifReader.running = false
      notifReader.running = true
    }
  }
  SafeProcess {
    id: notifReader
    command: Model.bounded(["bash", "-c", root.readFile, "read", root.notifFile], 3, 65536)
    stdout: StdioCollector { onStreamFinished: root.notifLoaded(Model.capped(text, 65536)) }
  }
  function notifLoaded(t) {
    if (t === null || t === "") return
    var d = null
    try { d = JSON.parse(t) } catch (e) { return }
    if (!d || typeof d !== "object") return
    var summary = Model.plainText(d.summary)
    var body = Model.plainText(d.body)
    if (summary === "" && body === "") return
    var pn = root.relayed(d)
    // The phone is right there showing this itself.
    if (pn && root.phoneMuted) return
    // The same message can arrive from the phone and from this machine's own
    // copy of the app (Signal, WhatsApp, Telegram): whichever lands first wins.
    var line = pn ? root.newestLine(pn.text) : (body !== "" ? body : summary)
    if (Model.seenRecently(root.recentMessages, line, Date.now(), root.duplicateWindow)) return
    root.recentMessages = Model.rememberMessage(root.recentMessages, line, Date.now(), root.duplicateWindow)
    var iconUrl = root.notifIcon(d, summary)
    var file = root.notifFile.substring(root.notifFile.lastIndexOf("/") + 1)
    root.pushActivity({
      kind: "notification", source: "notification", file: file,
      app: root.notifApp(d, summary),
      title: pn ? String(pn.title) : (summary !== "" ? summary : body),
      body: pn ? root.newestLine(pn.text) : (summary !== "" ? body : ""), image: iconUrl,
      replyId: pn ? String(pn.replyId || "") : "",
      phone: !!pn, fullText: pn ? String(pn.text) : "",
      urgent: Number(d.urgency) === 2,
      duration: Number(d.urgency) === 2 ? 8000 : 5000
    })
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
  // What is known about a relayed notification: the phone's own entry while it
  // is still on the phone, and once it is gone, the relayed line itself, which
  // is still "<title>: <text>" with its <br/> message breaks intact.
  function relayed(d) {
    if (String(d.app || "") !== phoneRelay) return null
    var live = root.phoneNotif(d)
    if (live) return live
    var body = Model.plainText(d.body)
    var cut = body.indexOf(": ")
    if (cut < 0) return { title: Model.plainText(d.summary), text: body, replyId: "", icon: "" }
    return { title: body.slice(0, cut), text: body.slice(cut + 2), replyId: "", icon: "" }
  }
  function notifApp(d, summary) {
    var app = String(d.app || "")
    return app === phoneRelay && String(summary || "") !== "" ? String(summary) : app
  }
  function notifIcon(d, summary) {
    if (String(d.app || "") === phoneRelay && root.phone) {
      var pn = root.relayed(d)
      var chats = root.phone.pstate.phoneChats || {}
      var icon = pn && String(pn.icon || "") !== "" ? String(pn.icon)
        : String((pn ? chats[String(summary || "") + "\u0000" + pn.title] : "")
                 || (root.phone.pstate.phoneApps || {})[String(summary || "")] || "")
      if (icon !== "") return icon.indexOf("/") === 0 ? "file://" + icon : icon
    }
    // Omarchy copies a notification's files under its images folder before it
    // writes the JSON, so a path anywhere else (or a URL) is not one of those
    // copies and is ignored; a bare name is a themed icon.
    var image = root.notifImage(d.image)
    if (image !== "") return image
    var appIcon = String(d.appIcon || "")
    if (appIcon.indexOf("/") !== -1 || appIcon.indexOf(":") !== -1) {
      var copy = root.notifImage(appIcon)
      if (copy !== "") return copy
    } else if (appIcon !== "" && appIcon.length <= 128) return Quickshell.iconPath(appIcon, true)
    return root.appIconFor(notifApp(d, summary))
  }
  readonly property string notifImages: root.notifDir + "/images/"
  function notifImage(v) {
    var u = Model.localImage(v)
    return u.indexOf("file://" + root.notifImages) === 0 ? u : ""
  }

  // No reply handle (Gmail, GPay…): the next best thing is that app on this
  // machine — most of them are Omarchy webapps, which open on the right service.
  function openForApp(app) {
    var name = String(app || "").trim()
    if (name === "") return false
    var entry = typeof DesktopEntries.heuristicLookup === "function" ? DesktopEntries.heuristicLookup(name) : null
    var id = entry ? String(entry.id || "") : ""
    if (!/^[A-Za-z0-9._-]{1,128}$/.test(id)) return false
    // The way Omarchy's launcher starts apps: as a session unit, so the app
    // gets the session's environment rather than the shell's.
    root.launch(["uwsm-app", "--", "gtk-launch", id + ".desktop"])
    return true
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

  // What the island has shown lately, so the second copy of one message is
  // dropped no matter which side it comes from: phoned reading the phone, KDE
  // Connect mirroring the phone's popup, or the desktop app for the same chat.
  property var recentMessages: []
  readonly property int duplicateWindow: 12000
  property var pendingThread: null
  property var pendingNotif: null
  function notificationActivate() {
    if (activity && activity.sms) {
      controlsRequested("messages")
      pendingThread = activity.sms
      finishActivity()
      return
    }
    if (activity && activity.phone) {
      // Phone notifications open in full: every line, the picture, the reply box.
      pendingNotif = activity
      controlsRequested("notif")
      finishActivity()
      return
    }
    if (activity && root.openForApp(activity.app)) {
      finishActivity()
      return
    }
    root.fire(["omarchy-shell", "-q", "notifications", "invokeLast"], 10)
    finishActivity()
  }
  function notificationDismiss() {
    root.fire(["omarchy-shell", "-q", "notifications", "dismissOne"], 10)
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
    // Every transient passes through here, whoever raised it (IPC, OSD,
    // Bluetooth names, keyboard layouts, messages), so this is where their
    // text is held to a sane length.
    t = Object.assign({}, t, {
      icon: Model.clip(t.icon, 16), app: Model.clip(t.app, 80), title: Model.clip(t.title, 200),
      value: Model.clip(t.value, 60), body: Model.clip(t.body, 2000),
      duration: Model.clamp(Number(t.duration) || 2500, 500, 30000)
    })
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
    // The mirror's own window is the indicator; a second one on this desktop
    // counting how long the phone has been up says nothing the phone doesn't.
    if (phoneMirroring && !phoneMuted) out.push("phone")
    if (timerActive) out.push("timer")
    if (stopwatchActive) out.push("stopwatch")
    if (mediaLive) out.push("media")
    return out
  }
  readonly property string live: lives.length > 0 ? lives[0] : ""
  readonly property string secondLive: lives.length > 1 ? lives[1] : ""

  // ------------------------------------------------------------ volume by scroll
  function scrollVolumeBy(delta) {
    if (!root.scrollVolume) return
    root.fire(["omarchy-audio-output-volume", delta > 0 ? "+2" : "-2"], 5)
  }

  // ------------------------------------------------------------ earbuds
  // OnePlus Experience's own service, loaded from its plugin folder when it's
  // installed, so the Control Center drives the buds through the same code
  // path as that plugin's panel.
  readonly property string budsServicePath: Quickshell.env("HOME") + "/.config/omarchy/plugins/io.github.buildscript-dev.oneplus-experience/Service.qml"
  property bool budsInstalled: false
  SafeProcess {
    running: true
    command: Model.bounded(["test", "-f", root.budsServicePath], 3, 0)
    onExited: function(code) { root.budsInstalled = code === 0 }
  }
  Loader {
    id: budsLoader
    active: root.budsInstalled
    source: active ? "file://" + root.budsServicePath : ""
  }
  readonly property var buds: budsLoader.item
  readonly property bool budsConnected: !!(buds && buds.status && buds.status.connected)
  readonly property string budsName: buds && buds.status && buds.status.deviceName ? buds.status.deviceName : "Earbuds"
  readonly property var budsModeNames: ({ smart: "Adaptive", anc: "Noise Cancellation", transparency: "Transparency", vocal: "Conversation", off: "Noise Control Off" })
  readonly property var budsModeGlyphs: ({ smart: "󰧑", anc: "󰟎", transparency: "󰈈", vocal: "󰗋", off: "󰋋" })
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
  property bool phoneInstalled: false
  SafeProcess {
    running: true
    command: Model.bounded(["test", "-f", root.phoneServicePath], 3, 0)
    onExited: function(code) { root.phoneInstalled = code === 0 }
  }
  Loader {
    id: phoneLoader
    active: root.phoneInstalled
    source: active ? "file://" + root.phoneServicePath : ""
    onLoaded: item.refresh()
  }
  readonly property var phone: phoneLoader.item
  readonly property bool phoneMirroring: !!(phone && phone.sessionRunning)
  // The mirror as the compositor sees it, so a window Taildroid did not start
  // itself counts too: a DeX display, a single mirrored app, a bare scrcpy.
  readonly property bool mirrorWindowOpen: {
    var list = ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []
    for (var i = 0; i < list.length; i++) {
      var id = String(list[i].appId || "").toLowerCase()
      if (id.indexOf("taildroid") !== -1 || id.indexOf("scrcpy") !== -1) return true
    }
    return false
  }
  readonly property bool phoneOnScreen: phoneMirroring || mirrorWindowOpen
  // ponytail: "on screen" means a mirror window exists, not that it is on the
  // workspace you are looking at — park the mirror elsewhere and the island
  // still holds its tongue. Per-workspace visibility needs the Hyprland client
  // list; add it if parking the mirror turns out to be the normal way to work.
  readonly property bool phoneMuted: muteWhileMirrored && phoneOnScreen
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
  readonly property string phoneName: phone && phone.pstate && phone.pstate.phone && phone.pstate.phone.model ? phone.pstate.phone.model : "Phone"
  Connections {
    target: root.phone
    ignoreUnknownSignals: true
    function onPhoneEvent(ev) {
      if (!root.settled) return
      // Connected, nearby, hotspot: the mirror shows the phone's own status
      // bar, so these say nothing new while it is open. Calls and errors still
      // come through — those are worth interrupting for.
      if (root.phoneMuted && (ev.kind === "connected" || ev.kind === "disconnected"
          || ev.kind === "nearby" || ev.kind === "hotspot")) return
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
        var text = String(ev.body || "")
        var dup = Model.seenRecently(root.recentMessages, text, Date.now(), root.duplicateWindow)
        root.recentMessages = Model.rememberMessage(root.recentMessages, text, Date.now(), root.duplicateWindow)
        if (root.showNotifications && !root.phoneMuted && !dup)
          root.pushActivity({ kind: "notification", source: "sms", file: "", app: "Messages · " + root.phoneName,
            title: ev.name || (ev.addresses || []).join(", "), body: text, image: "",
            urgent: false, duration: 6000, sms: ev })
      }
      else if (ev.kind === "error")
        root.pushActivity({ kind: "alert", source: "phone-error", icon: "󰀦", tint: "orange", title: String(ev.message || "Phone").slice(0, 60), value: "", duration: 3500 })
    }
  }

  // ------------------------------------------------------------ system update
  property bool updateAvailable: false
  SafeProcess {
    id: updateCheck
    command: Model.bounded(["omarchy-update-available"], 120, 0)
    onExited: function(code) { root.updateAvailable = code === 0 }
  }
  Timer { interval: 21600000; running: root.onlineExtras; repeat: true; triggeredOnStart: true; onTriggered: updateCheck.running = true }
  function checkUpdates() { if (root.onlineExtras && !updateCheck.running) updateCheck.running = true }
  function runUpdate() { root.launch(["omarchy-launch-floating-terminal-with-presentation", "omarchy-update"]) }

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
  SafeProcess {
    id: weatherRead
    command: Model.bounded(["omarchy-weather-status"], 30, 4096)
    stdout: StdioCollector {
      onStreamFinished: {
        var t = Model.clip(String(Model.capped(text, 4096) || "").trim(), 120)
        if (t === "" || t.indexOf("unavailable") !== -1) return
        var parts = t.split("·").map(function(x) { return x.trim() })
        root.weatherPlace = parts[0] || ""
        root.weatherTemp = (parts[1] || "").replace(/^Temp\s*/, "")
        root.weatherText = root.weatherPlace + (root.weatherTemp ? " · " + root.weatherTemp : "")
      }
    }
  }
  Timer { interval: 1800000; running: root.onlineExtras; repeat: true; triggeredOnStart: true; onTriggered: if (!weatherRead.running) weatherRead.running = true }
  onOnlineExtrasChanged: {
    fetchArt()
    if (!onlineExtras) { weatherText = ""; weatherPlace = ""; weatherTemp = ""; updateAvailable = false }
  }

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
  // Taildroid loads after the history is first read, so the phone's chat names
  // and pictures land late; read it again once they arrive.
  property int phoneChatCount: phone && phone.pstate.phoneChats ? Object.keys(phone.pstate.phoneChats).length : 0
  onPhoneChatCountChanged: readHistory()
  function readHistory() {
    if (historyRead.running) { historyAgain = true; return }
    historyRead.running = true
  }
  property bool historyAgain: false
  // The newest 50 entries (Omarchy keeps 10), 32 KB each at most — a longer
  // one is cut off, fails to parse and is skipped — and 2 MB in all.
  SafeProcess {
    id: historyRead
    command: Model.bounded(["bash", "-c",
      "/usr/bin/ls -1r -- \"$1\" 2>/dev/null | /usr/bin/grep -E '^[A-Za-z0-9._-]+\\.json$' | /usr/bin/head -n 50 | " +
      "while IFS= read -r n; do f=\"$1/$n\"; [ -f \"$f\" ] && [ ! -L \"$f\" ] || continue; " +
      "printf '%s\\t' \"$n\"; /usr/bin/head -c 32768 -- \"$f\" | /usr/bin/tr -d '\\n'; echo; done",
      "history", root.historyDir], 5, 2097152)
    stdout: StdioCollector {
      onStreamFinished: {
        var out = []
        var lines = String(Model.capped(text, 2097152) || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var tab = lines[i].indexOf("\t")
          if (tab < 0) continue
          try {
            var d = JSON.parse(lines[i].substring(tab + 1))
            var summary = Model.plainText(d.summary)
            var pn = root.relayed(d)
            out.push({ file: lines[i].substring(0, tab), app: root.notifApp(d, summary),
              title: pn ? String(pn.title) : summary,
              body: pn ? root.newestLine(pn.text) : Model.plainText(d.body),
              time: Number(d.timestamp) || 0, urgent: Number(d.urgency) === 2,
              replyId: pn ? String(pn.replyId || "") : "",
              phone: !!pn, fullText: pn ? String(pn.text) : "",
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
    root.fire(["omarchy-shell", "-q", "notifications", "clear"], 10)
    history = []
  }
  function removeHistory(file) {
    if (!/^[A-Za-z0-9._-]+\.json$/.test(file)) return
    root.fire(["bash", "-c", "/usr/bin/rm -f -- \"$1/$3\" \"$2/${3%.json}\"-*", "rm", root.historyDir, root.notifDir + "/images", file], 5)
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
  // A number handed over by `island dial`, for the keypad to pick up.
  property string pendingDial: ""
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
      if (String(payloadJson || "").length > 4096) return "too-long"
      var p = {}
      try { p = JSON.parse(payloadJson || "{}") } catch (e) { return "bad-json" }
      if (!p || typeof p !== "object") return "bad-json"
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

  // Anything in this session can call these, so they only change what the
  // island shows. Nothing here places a call, sends a message or reads one
  // out: `state` reports what kind of thing is showing, never its text, and
  // `dial` only fills in the keypad — the call still takes a click.
  readonly property var ipcPages: ["main", "wifi", "bluetooth", "audio", "buds", "phone", "call", "messages", "thread", "notifications", "calendar", "power"]
  IpcHandler {
    target: "island"
    function state(): string {
      return JSON.stringify({
        live: root.live, second: root.secondLive, controls: root.controlsShown,
        activity: root.activity ? { kind: root.activity.kind, source: String(root.activity.source).indexOf("ipc-") === 0 ? "ipc" : root.activity.source } : null,
        queued: root.queue.length,
        media: { playing: root.isPlaying, player: root.playerName },
        timerLeft: Math.round(root.timerLeft), stopwatch: Math.floor(root.stopwatchElapsed), alarm: root.alarmAt > 0 ? Model.clockText(root.alarmAt) : "", recording: root.recording, micInUse: root.micInUse, cameraInUse: root.cameraInUse,
        battery: root.batteryPercent, charging: root.charging, dnd: root.dnd,
        phone: { mirrored: root.phoneOnScreen, muted: root.phoneMuted },
        shape: root.shape, monitor: root.monitor, style: root.style, palette: root.paletteName, font: root.textFont, notchHeight: root.notchHeight
      })
    }
    function ping(): string { return "ok" }
    function expand(): string { root.expandRequested(); return "ok" }
    // Open the Control Center, optionally on a page: wifi, bluetooth, audio,
    // buds, phone, notifications, calendar, power.
    function controls(page: string): string {
      var p = String(page || "main")
      if (root.ipcPages.indexOf(p) === -1) return "unknown-page"
      root.controlsRequested(p)
      return "ok"
    }
    // Taildroid mirroring on/off (Super+Shift+I).
    function phoneToggle(): string { if (!root.phone) return "no-taildroid"; root.phone.toggleControl(); return "ok" }
    function collapse(): string { root.collapseAll(); return "ok" }
    // Phone continuity from the keyboard. `answer` only picks up a call that
    // is ringing on screen right now; `hangup` ends one; `dial` opens the
    // keypad with the number in it and leaves the call button to the user.
    function answer(): string {
      if (!root.phone) return "no-taildroid"
      if (!root.ringingCall) return "not-ringing"
      root.phone.answer(String(root.ringingCall.path || ""))
      return "ok"
    }
    function hangup(): string { if (!root.phone) return "no-taildroid"; root.phone.hangup(""); return "ok" }
    function dial(number: string): string {
      if (!root.phone) return "no-taildroid"
      var n = String(number || "")
      if (!/^[0-9*#+]{1,32}$/.test(n)) return "bad-number"
      root.pendingDial = n
      root.controlsRequested("call")
      return "ok"
    }
    function messages(): string { root.controlsRequested("messages"); return "ok" }
    function phoneDex(): string { if (!root.phone) return "no-taildroid"; root.phone.openDex(); return "ok" }
    function timer(seconds: string): string {
      var n = Number(seconds)
      if (!isFinite(n) || n < 1 || n > 86400) return "bad-seconds"
      root.startTimer(n)
      return "ok"
    }
    function timerCancel(): string { root.cancelTimer(); return "ok" }
    function stopwatch(): string { root.toggleStopwatch(); return "ok" }
    function stopwatchReset(): string { root.resetStopwatch(); return "ok" }
    function alarm(hhmm: string): string { return root.setAlarm(hhmm) ? "ok" : "bad-time" }
    function alarmCancel(): string { root.cancelAlarm(); return "ok" }
    function alert(icon: string, title: string, value: string): string {
      root.pushActivity({ kind: "alert", source: "ipc-alert", icon: Model.clip(icon, 4), tint: "white",
        title: Model.clip(title, 60), value: Model.clip(value, 24), duration: 2500 })
      return "ok"
    }
    function hud(icon: string, percent: string): string {
      root.pushActivity(Model.osdTransient({ icon: Model.clip(icon, 32), value: Model.clip(percent, 8) }))
      return "ok"
    }
    function notify(title: string, body: string): string {
      root.pushActivity({ kind: "notification", source: "ipc-notify", file: "", app: "Dynamic Island",
        title: Model.clip(title, 120), body: Model.clip(body, 400), image: "", urgent: false, duration: 5000 })
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
