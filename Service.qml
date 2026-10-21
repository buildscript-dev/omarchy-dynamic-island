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
import "Registry.js" as Registry

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
  function fire(argv, seconds, extraEnv) {
    Quickshell.execDetached({ command: Model.bounded(argv, seconds || 20, 0), environment: Object.assign({}, root.childEnv, extraEnv || {}), clearEnvironment: true })
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

  readonly property string paletteName: String(setting("palette", "apple"))   // apple | theme (QQuickItem already owns "palette")
  // iPhone 15/16 Pro size (HIG: 36.67 pt tall, camera about 126 wide). The gap above stays your pillInset: a desktop has no bezel to spend it on.
  readonly property bool appleSize: setting("appleSize", false) === true
  readonly property int notchWidth: appleSize ? 126 : Number(setting("islandWidth", 96))
  // iOS: tap a live activity opens its app, touch and hold expands it.
  readonly property bool tapOpensApp: setting("tapOpensApp", false) === true
  // iOS: an alert lights the screen and plays the notification sound.
  readonly property bool alertSound: setting("alertSound", true) === true
  // A desktop has no haptic motor: a soft tick on press, hold and swipe stands in for it.
  readonly property bool haptics: setting("haptics", true) === true
  readonly property string tickFile: String(Qt.resolvedUrl("sounds/tick.wav")).replace(/^file:\/\//, "")
  function tick() {
    if (haptics && /^\/[A-Za-z0-9._\/-]+\.wav$/.test(tickFile))
      root.fire(["pw-play", "--volume=0.4", tickFile], 3)
  }
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
  readonly property bool reduceMotion: setting("reduceMotion", false) === true
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
  readonly property int barHeight: barPosition === "top" ? Style.bar.sizeHorizontal : Math.max(26, Style.bar.sizeHorizontal)
  // The island floats a little below the top edge, iPhone-style, at its own height.
  readonly property int islandTop: Math.max(0, Number(setting("pillInset", 6)))
  readonly property int notchHeight: appleSize ? 37 : Math.max(20, Number(setting("islandHeight", 30)))

  // ------------------------------------------------------------ look
  // Pure black, like the iPhone: it melts into the camera and the bezel.
  readonly property color islandColor: "#000000"
  // Containers take a dark wash of what they show: the app icon, the kind of alert, the cover art,
  // or the Omarchy theme accent. Off = plain black.
  readonly property bool tintContainers: setting("tintContainers", true) === true
  readonly property color themeAccent: Color.accent
  readonly property color textColor: "#ffffff"
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

  // Inter (OFL, Latin subset) ships with the plugin, so the island has the same
  // font on every machine. A system Inter or SF Pro still wins in textFont.
  FontLoader { id: interRegular; source: Qt.resolvedUrl("fonts/Inter-Regular.ttf") }
  FontLoader { source: Qt.resolvedUrl("fonts/Inter-Medium.ttf") }
  FontLoader { source: Qt.resolvedUrl("fonts/Inter-SemiBold.ttf") }
  FontLoader { source: Qt.resolvedUrl("fonts/Inter-Bold.ttf") }
  FontLoader { id: interDisplay; source: Qt.resolvedUrl("fonts/Inter-Display-Regular.ttf") }
  FontLoader { source: Qt.resolvedUrl("fonts/Inter-Display-Bold.ttf") }
  readonly property bool interReady: interRegular.status === FontLoader.Ready && interDisplay.status === FontLoader.Ready
  readonly property string textFont: {
    var loaded = interReady   // Qt.fontFamilies() is not reactive: re-run once the bundled faces are in
    // Text cuts first: the island's text is 13-14 px, where Apple uses SF Pro
    // Text; the Display cuts are drawn for 20 px and up.
    // "Inter Island" is the copy shipped with the plugin, under its own name: a second "Inter" next to the system one
    // makes Qt draw one file's glyph numbers with the other file's outlines (symbols instead of letters).
    var want = ["SF Pro Text", "SF Pro", "SF Pro Display", "Inter", "Inter Variable", "Inter Display", "Inter Island", "Noto Sans", "Cantarell"]
    var have = Qt.fontFamilies()
    for (var i = 0; i < want.length; i++)
      if (have.indexOf(want[i]) !== -1) return want[i]
    return Style.font.family
  }
  // For the big clocks (20 px and up): the Display cut when there is one.
  readonly property string displayFont: {
    var loaded = interReady
    var have = Qt.fontFamilies()
    if (textFont.indexOf("SF Pro") === 0 && have.indexOf("SF Pro Display") !== -1) return "SF Pro Display"
    if (textFont === "Inter Island" && have.indexOf("Inter Island Display") !== -1) return "Inter Island Display"
    if (textFont.indexOf("Inter") === 0 && have.indexOf("Inter Display") !== -1) return "Inter Display"
    return textFont
  }
  FontLoader { id: phosphorFont; source: Qt.resolvedUrl("fonts/Phosphor-Fill.ttf") }
  readonly property string iconFont: {
    if (phosphorFont.status === FontLoader.Ready) return phosphorFont.name
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
  // Set while you page to a particular player in the opened island (a music
  // app or a browser tab), so that page keeps showing it.
  property string pinnedPlayerKey: ""
  readonly property var mediaPlayers: players.filter(function(p) { return p && (p.trackTitle || p.trackArtist) })
  readonly property var player: {
    if (root.pinnedPlayerKey !== "")
      for (var j = 0; j < mediaPlayers.length; j++)
        if (Model.playerKey(mediaPlayers[j]) === root.pinnedPlayerKey) return mediaPlayers[j]
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
  // keeps exactly one image there (plus the alarm time) — and only that copy is drawn and tinted.
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
    "/usr/bin/find \"$d\" -maxdepth 1 -type f \\( -name \"*.img\" ! -name \"${f##*/}\" -mmin +1440 -o -name \"art.*\" -mmin +1 \\) -delete; printf %s \"$f\""
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
      // Remote artwork: downloaded only with onlineExtras on.
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

  // ------------------------------------------------------------ AI on the phone
  // Taildroid's MCP server calls `island aiActivity` on every phone action, so
  // it's always visible while an assistant is driving the phone.
  property real aiUntil: 0
  property string aiText: ""
  property string aiLabel: "Phone"   // who is at work
  readonly property bool aiActive: { root.now; return aiUntil > Date.now() }

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
  function resetStopwatch() {
    if (stopwatchElapsed >= 1) logRecent(glyphs.stopwatch, "orange", "Stopwatch", Model.formatTime(stopwatchElapsed))
    stopwatchSince = 0; stopwatchHeld = -1
  }

  // ------------------------------------------------------------ alarm
  // One alarm. Its time is kept in the private run directory (the same 0700
  // one as the album art), so it survives a shell restart. A reboot clears
  // /run/user, and a sleeping laptop could not ring anyway.
  // When it goes off it rings until stopped, like a phone: click the pill to
  // stop, right-click to snooze 9 minutes. Other activities wait behind it
  // (see pushActivity). It gives up after 5 minutes.
  property real alarmAt: 0          // epoch ms; 0 = none
  property bool alarmRinging: false
  property real alarmRingSince: 0
  readonly property string alarmDir: "d=\"/run/user/$UID/omarchy-dynamic-island\"; f=\"$d/alarm\"; "
  function setAlarm(hhmm) {
    var at = Model.nextAlarm(hhmm, Date.now())
    if (!at) return false
    armAlarm(at)
    pushActivity({ kind: "alert", source: "alarm", icon: glyphs.alarm, tint: "orange", title: "Alarm", value: Model.clockText(at), duration: 1600 })
    return true
  }
  function armAlarm(at) { alarmAt = at; saveAlarm() }
  function cancelAlarm() { alarmAt = 0; saveAlarm() }
  function saveAlarm() {
    root.fire(["bash", "-c", root.alarmDir + "umask 077; /usr/bin/mkdir -p -m 700 -- \"$d\" 2>/dev/null; " +
      "[ -d \"$d\" ] && [ ! -L \"$d\" ] && [ -O \"$d\" ] || exit 1; " +
      "if [ \"$1\" = 0 ]; then /usr/bin/rm -f -- \"$f\"; else [ ! -L \"$f\" ] && printf %s \"$1\" > \"$f\"; fi",
      "alarm", String(Math.round(root.alarmAt))], 5)
  }
  SafeProcess {
    running: true
    command: Model.bounded(["bash", "-c", root.alarmDir + "[ -f \"$f\" ] && [ ! -L \"$f\" ] && exec /usr/bin/cat -- \"$f\""], 3, 32)
    stdout: StdioCollector {
      onStreamFinished: {
        var at = Model.restoredAlarm(Model.capped(text, 32), Date.now())
        if (at) root.alarmAt = at
        else if (text !== "") root.saveAlarm()   // stale: it went off while the shell was down
      }
    }
  }
  Timer {
    interval: 1000
    repeat: true
    running: root.alarmAt > 0
    onTriggered: {
      if (Date.now() < root.alarmAt) return
      var at = root.alarmAt
      root.cancelAlarm()
      root.pushActivity({ kind: "alert", source: "alarm-ring", icon: root.glyphs.alarm, tint: "orange", title: "Alarm", value: Model.clockText(at), duration: 30000 })
      activityTimer.stop()          // held until stopped, snoozed or replaced
      root.alarmRingSince = Date.now()
      root.alarmRinging = true
    }
  }
  function stopAlarm() {
    if (!alarmRinging) return
    alarmRinging = false
    if (activity && activity.source === "alarm-ring") finishActivity()
  }
  function snoozeAlarm() {
    if (!alarmRinging) return false
    stopAlarm()
    armAlarm(Date.now() + 9 * 60000)
    return true
  }
  onActivityChanged: if (alarmRinging && (!activity || activity.source !== "alarm-ring")) alarmRinging = false
  // ponytail: a stop lets the current 6 s sound finish; kill pw-play if that bothers anyone.
  Timer {
    interval: 6500
    repeat: true
    running: root.alarmRinging
    triggeredOnStart: true
    onTriggered: {
      if (Date.now() - root.alarmRingSince > 5 * 60000) { root.stopAlarm(); return }
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
      if (!on && root.recording && root.recordingSince > 0)
        root.logRecent(root.glyphs.record, "red", "Screen recording", Model.formatTime((Date.now() - root.recordingSince) / 1000))
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

  // ------------------------------------------------------------ Wi-Fi, Tailscale, USB
  // One short check every 5 s (NetworkManager's device list and the names of the
  // USB devices): a pill when the Wi-Fi network changes, Tailscale goes up or
  // down (that is the link to the phone), or a USB device comes or goes.
  // ponytail: a poll, not udev / D-Bus events; swap for `nmcli monitor` + udev if
  // 5 s ever feels slow. A change must hold for two reads, so a suspend or a
  // roam does not flash "Disconnected" then "Connected".
  property bool hwLoaded: false
  property string wifiSeen: ""
  property int wifiHold: 0
  property bool tailSeen: false
  property int tailHold: 0
  property var usbNow: []
  Timer { interval: 5000; repeat: true; running: true; triggeredOnStart: true
    onTriggered: if (!hwRead.running) hwRead.running = true }
  SafeProcess {
    id: hwRead
    command: Model.bounded(["bash", "-c", "/usr/bin/nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device 2>/dev/null; echo ===USB; for d in /sys/bus/usb/devices/*/product; do [ -f \"$d\" ] && /usr/bin/cat -- \"$d\"; done"], 5, 16384)
    stdout: StdioCollector { onStreamFinished: root.hwLoad(Model.capped(text, 16384)) }
  }
  function hwPill(icon, tint, title, value) {
    pushActivity({ kind: "alert", source: "hw", icon: icon, tint: tint, title: Model.clip(title, 40), value: value, duration: 2400 })
  }
  function hwLoad(t) {
    if (t === null || t === "") return
    var parts = String(t).split("===USB\n")
    var wifi = "", tail = false
    var net = parts[0].split("\n")
    for (var i = 0; i < net.length; i++) {
      var f = Model.nmcliFields(net[i])   // a lookbehind split never matched in Qt: these pills never fired
      if (f.length < 4) continue
      if (f[1] === "wifi" && f[2] === "connected") wifi = f[3]
      if (f[0] === "tailscale0") tail = /^connected/.test(f[2])
    }
    var usb = (parts[1] || "").split("\n").map(function(x) { return x.trim() })
      .filter(function(x) { return x !== "" && !/host controller|root hub/i.test(x) })
    var first = !hwLoaded
    var live = !first && settled
    // Wi-Fi: a new state has to be read twice before it counts.
    if (wifi !== wifiSeen) { wifiHold++; if (wifiHold >= 2 || first) { if (live) hwPill(glyphs.wifi, wifi !== "" ? "green" : "secondary", wifi !== "" ? wifi : "Wi-Fi", wifi !== "" ? "Connected" : "Disconnected"); wifiSeen = wifi; wifiHold = 0 } }
    else wifiHold = 0
    if (tail !== tailSeen) { tailHold++; if (tailHold >= 2 || first) { if (live) hwPill(glyphs.check, tail ? "green" : "secondary", "Tailscale", tail ? "Connected" : "Disconnected"); tailSeen = tail; tailHold = 0 } }
    else tailHold = 0
    if (live) {
      var added = usb.filter(function(x) { return usbNow.indexOf(x) === -1 })
      var gone = usbNow.filter(function(x) { return usb.indexOf(x) === -1 })
      if (added.length > 0) hwPill(glyphs.power, "green", added[0], "Connected")
      else if (gone.length > 0) hwPill(glyphs.power, "secondary", gone[0], "Removed")
    }
    usbNow = usb
    hwLoaded = true
  }

  // ------------------------------------------------------------ night light, stay awake
  // The iPhone shows a pill when a Focus or a mode flips. Omarchy's two modes
  // are flipped from keybinds and menus, so ask for their state. ponytail: a 5 s
  // poll (two short processes); a file watch would do if they ever get a state file
  // we can watch for night light.
  property int modeLoaded: 0
  property bool nightOn: false
  property bool awakeOn: false
  Timer { interval: 5000; repeat: true; running: true; triggeredOnStart: true
    onTriggered: { if (!nightRead.running) nightRead.running = true; if (!awakeRead.running) awakeRead.running = true } }
  function modeChanged(flag, on, glyph, tint, title) {
    if (root.settled && (root.modeLoaded & flag) && on !== (flag === 1 ? root.nightOn : root.awakeOn))
      root.pushActivity({ kind: "alert", source: "mode-" + flag, icon: glyph, tint: tint, title: title, value: on ? "On" : "Off", duration: 1800 })
    root.modeLoaded |= flag
  }
  SafeProcess {
    id: nightRead
    command: Model.bounded(["omarchy-toggle-nightlight", "--status"], 5, 4096)
    stdout: StdioCollector { onStreamFinished: {
      try { var on = !!JSON.parse(Model.capped(text, 4096)).enabled; root.modeChanged(1, on, root.glyphs.sun, "orange", "Night Light"); root.nightOn = on } catch (e) {}
    } }
  }
  SafeProcess {
    id: awakeRead
    command: Model.bounded(["omarchy-toggle-idle", "--status"], 5, 4096)
    stdout: StdioCollector { onStreamFinished: {
      try { var on = !!JSON.parse(Model.capped(text, 4096)).enabled; root.modeChanged(2, on, root.glyphs.coffee, "yellow", "Stay Awake"); root.awakeOn = on } catch (e) {}
    } }
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
    // A blanked-out SMS notification says nothing; while the phone's SMS sync is up, the SMS itself brings the card.
    var kc = root.phone && root.phone.pstate ? root.phone.pstate.kdeconnect || {} : {}
    if (Model.isRedacted({ body: pn ? String(pn.text) : body }) && kc.reachable && kc.sharing && kc.sharing.sms) return
    if (root.seenMessage(line, Model.otpCode(summary + " " + (pn ? String(pn.text) : body)))) return
    var iconUrl = root.notifIcon(d, summary)
    var file = root.notifFile.substring(root.notifFile.lastIndexOf("/") + 1)
    if (root.alertSound && !root.dnd) root.fire(["pw-play", "/usr/share/sounds/freedesktop/stereo/message-new-instant.oga"], 5)
    root.pushActivity({
      kind: "notification", source: "notification", file: file,
      app: root.notifApp(d, summary),
      title: pn ? String(pn.title) : (summary !== "" ? summary : body),
      body: pn ? root.newestLine(pn.text) : (summary !== "" ? body : ""), image: iconUrl,
      replyId: pn ? String(pn.replyId || "") : "",
      phone: !!pn, fullText: pn ? String(pn.text) : "",
      urgent: Number(d.urgency) === 2, execArgv: String(d.execArgv || ""),
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
  readonly property string focusKeep: 'pos=$(/usr/bin/hyprctl cursorpos) || exit 1; x=${pos%%,*}; y=${pos##*, }; '
    + '[[ $x =~ ^-?[0-9]+$ && $y =~ ^-?[0-9]+$ ]] || exit 1; /usr/share/omarchy/bin/omarchy-launch-or-focus "$1" "$2"; sleep 0.08; '
    + '/usr/bin/hyprctl dispatch "hl.dsp.cursor.move({ x = $x, y = $y })" >/dev/null 2>&1'
  function openForApp(app) {
    var name = String(app || "").trim()
    if (name === "") return false
    var entry = typeof DesktopEntries.heuristicLookup === "function" ? DesktopEntries.heuristicLookup(name) : null
    var id = entry ? String(entry.id || "") : ""
    if (!/^[A-Za-z0-9._-]{1,128}$/.test(id)) return false
    // Focus the app's open window; only start it when it has none. Omarchy's
    // own helper, and the launch is the way its launcher starts apps: a
    // session unit, so the app gets the session's environment.
    var cls = String(entry.startupClass || id)
    if (!/^[A-Za-z0-9._-]{1,128}$/.test(cls)) cls = id
    // Focusing warps the cursor to the window; put it back, so a click on the
    // island leaves the pointer where it was.
    root.launch(["bash", "-c", root.focusKeep, "focus-keep", cls, "uwsm-app -- gtk-launch " + id + ".desktop"])
    return true
  }

  // Tap on the playing track: bring up its player. ponytail: gtk-launch, so a player
  // without single-instance handling opens a second window; focus by class if that bites.
  function openPlayerApp() {
    var p = root.player
    return p ? root.openForApp(String(p.desktopEntry || p.identity || "")) : false
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
  // A one-time code on a card: the one BuildDots read from the SMS itself (island otp), else whatever a
  // notification's text holds (Model.otpCode says which digits count).
  function codeOf(n) {
    if (!n) return ""
    if (/^\d{4,8}$/.test(String(n.code || ""))) return String(n.code)
    return Model.otpCode(root.textOf(n))
  }
  // A card's whole message: a phone notification shows only its newest line, the code can sit in any of them.
  function textOf(n) {
    return n ? String(n.title || "") + " " + String(n.fullText || n.body || "") : ""
  }
  // Copy a code. --sensitive keeps it out of the clipboard history (capture.sh skips that hint); launch, not fire,
  // since wl-copy stays up to serve the paste. The card shows "Copied" in place for a moment, then folds.
  property string copiedCode: ""
  Timer { id: copiedReset; interval: 2400; onTriggered: root.copiedCode = "" }
  Timer { id: copiedFold; interval: 900; onTriggered: root.finishActivity() }
  function copyCode(code) {
    if (!/^\d{4,8}$/.test(String(code || ""))) return
    root.launch(["wl-copy", "--sensitive", "--", code])
    root.copiedCode = code
    copiedReset.restart()
  }
  // What a click on a notification card does, most specific first: a code is copied; the notification's own
  // action (Omarchy's omarchy-exec-argv hint, kept in its file) runs; the sending app comes forward. Omarchy's
  // invokeLast fires the newest popup on screen, whichever card was clicked, so it is used only for the live card
  // of that very notification. A history card once ran a crash report's "open Claude" this way.
  function openNotif(n, live, skipCode) {
    if (!n) return ""
    var code = skipCode ? "" : root.codeOf(n)
    if (code !== "") { root.copyCode(code); return "copied" }
    var argv = Model.execArgvOf(n.execArgv)
    if (argv) { root.launch(argv); return "ran" }
    if (root.openForApp(n.app)) return "opened"
    var newest = root.notifFile.substring(root.notifFile.lastIndexOf("/") + 1)
    if (live && n.source === "notification" && n.file !== "" && n.file === newest) {
      root.fire(["omarchy-shell", "-q", "notifications", "invokeLast"], 10)
      return "invoked"
    }
    return ""
  }
  function notificationActivate() {
    if (root.openNotif(activity, true, false) === "copied") { copiedFold.restart(); return }
    finishActivity()
  }
  // One message, one card: the phone's SMS, KDE Connect's copy of its notification and BuildDots' code card can
  // all carry the same thing. A message counts as seen by its text and, when it holds a code, by that code.
  function seenMessage(text, code) {
    var now = Date.now()
    var dup = Model.seenRecently(root.recentMessages, text, now, root.duplicateWindow)
      || (code !== "" && Model.seenRecently(root.recentMessages, "otp:" + code, now, root.duplicateWindow))
    var next = Model.rememberMessage(root.recentMessages, text, now, root.duplicateWindow)
    if (code !== "") next = Model.rememberMessage(next, "otp:" + code, now, root.duplicateWindow)
    root.recentMessages = next
    return dup
  }
  // Dismissing a phone notification here dismisses it on the phone too, through
  // KDE Connect: the phone's own notification object with the same title, and only
  // when the phone says it can be dismissed (a media player's cannot). The title
  // goes in through the environment (argv is world-readable in /proc), never into the script text.
  readonly property string dismissPhoneScript: "D=$(/usr/bin/kdeconnect-cli -a --id-only 2>/dev/null | /usr/bin/head -1)\n[ -n \"$D\" ] || exit 0\nN=/modules/kdeconnect/devices/$D/notifications\nI=org.kde.kdeconnect.device.notifications.notification\nfor id in $(/usr/bin/busctl --user call org.kde.kdeconnect \"$N\" org.kde.kdeconnect.device.notifications activeNotifications 2>/dev/null | /usr/bin/grep -o '\"[0-9A-Za-z_.:-]*\"' | /usr/bin/tr -d '\"'); do\n  t=$(/usr/bin/busctl --user get-property org.kde.kdeconnect \"$N/$id\" $I title 2>/dev/null)\n  [ \"$t\" = \"s \\\"$ISLAND_TITLE\\\"\" ] || continue\n  [ \"$(/usr/bin/busctl --user get-property org.kde.kdeconnect \"$N/$id\" $I dismissable 2>/dev/null)\" = \"b true\" ] || continue\n  /usr/bin/busctl --user call org.kde.kdeconnect \"$N/$id\" $I dismiss\n  exit 0\ndone\n"
  function notificationDismiss() {
    if (activity && activity.phone && String(activity.title || "") !== "")
      root.fire(["bash", "-c", root.dismissPhoneScript], 10, { ISLAND_TITLE: Model.clip(String(activity.title), 200) })
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
    if (t.source === "timer-done" || t.source === "alarm-ring" || t.source === "call")
      logRecent(t.icon, t.tint, t.title, t.value)
    // A ringing alarm keeps the island until someone acts on it: the rest
    // waits behind it, and a volume or brightness pill is skipped (the key
    // itself still works).
    if (alarmRinging && t.source !== "alarm-ring") {
      if (t.kind !== "hud") queue = queue.concat([t]).slice(-6)
      return
    }
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
    if (!activity || activity.source === "alarm-ring") return
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
  readonly property var activeLives: {
    var out = []
    if (currentCall) out.push("call")
    if (aiActive) out.push("ai")
    if (recording) out.push("recording")
    // The mirror's own window is the indicator; a second one on this desktop
    // counting how long the phone has been up says nothing the phone doesn't.
    if (phoneMirroring && !phoneMuted) out.push("phone")
    if (timerActive) out.push("timer")
    if (stopwatchActive) out.push("stopwatch")
    if (mediaLive) out.push("media")
    // Minimised windows wait at the island until you tap them back.
    if (dockCount > 0) out.push("dock")
    return out
  }
  // Swiping the island sideways tucks its activity away, as on iOS: the
  // timer keeps running and the expanded view still shows it; the pill
  // returns the next time that activity starts. A call, a recording and an
  // assistant driving the phone always stay in view.
  property var tucked: ({})
  readonly property var tuckable: ["timer", "stopwatch", "media", "phone"]
  // Scrolling on the island brings another running activity to the front
  // (pinnedLive); liveOrder is the order the scroll walks through.
  readonly property var liveOrder: activeLives.filter(function(k) { return !tucked[k] })
  property string pinnedLive: ""
  readonly property var lives: {
    var i = liveOrder.indexOf(pinnedLive)
    if (i <= 0) return liveOrder
    return [pinnedLive].concat(liveOrder.slice(0, i), liveOrder.slice(i + 1))
  }
  // The opened island's pages, in scroll order: each running activity at
  // full size, with one page per player that has a track (music apps and
  // browser tabs, playing or paused).
  readonly property var expandedPages: {
    var out = [], mediaDone = false
    function addPlayers() {
      if (mediaDone) return
      mediaDone = true
      for (var j = 0; j < mediaPlayers.length; j++)
        out.push({ kind: "media", key: Model.playerKey(mediaPlayers[j]) })
    }
    for (var i = 0; i < liveOrder.length; i++) {
      if (liveOrder[i] === "media") addPlayers()
      else if (liveOrder[i] !== "dock") out.push({ kind: liveOrder[i] })
    }
    addPlayers()
    return out
  }
  onActiveLivesChanged: {
    var t = {}, changed = false
    for (var k in tucked) { if (activeLives.indexOf(k) !== -1) t[k] = true; else changed = true }
    if (changed) tucked = t
  }
  function tuckLive() {
    if (tuckable.indexOf(live) === -1) return false
    var t = Object.assign({}, tucked)
    t[live] = true
    tucked = t
    return true
  }
  readonly property string live: lives.length > 0 ? lives[0] : ""
  readonly property string secondLive: lives.length > 1 ? lives[1] : ""

  // ------------------------------------------------------------ dock (minimised windows)
  // Super + drag a window onto the island and it flies in, narrowing like a genie
  // (Genie.qml), then waits here as a live activity: tap it and the window flies
  // back out. The windows sit on the special workspace `island`.
  property var docked: []            // [{ address, cls, title, rect: {x,y,w,h}, ws, snap }]
  readonly property int dockCount: docked.length
  // The newest minimised window's app icon, for the dock mark.
  readonly property string dockIcon: docked.length > 0 ? appIconFor(docked[docked.length - 1].cls) : ""
  property bool dockDragging: false
  property point dockPointer: Qt.point(-99999, -99999)
  property point dockOrigin: Qt.point(-99999, -99999)   // where the pointer was when the drag began   // layout coordinates, as hyprctl prints them
  signal dockDropRequested()
  signal dockMinimizeRequested()
  signal dockRestoreRequested(string address)
  function dockStart() {
    // A drag that never reported its release must not leave a window shrunk.
    if (dockDragging && !forcedFloat) dockUnshrink()
    dockDragging = true
    dockPointer = Qt.point(-99999, -99999)
    dockOrigin = Qt.point(-99999, -99999)
    dragPoll.running = false
    dragPoll.running = true
    dragScale = 0
    pendingPull = 0
    dragShrunk = false
    // Mid-pull on a window we floated, a second press must not lose what that window was.
    if (!forcedFloat) dragWin = null
    dragWinRead.running = false
    dragWinRead.running = true
  }
  function dockEnd() { dockDragging = false; dragPoll.running = false; shrinkTimer.stop() }
  // The window under the drag, and how far it is shrunk. It shrinks as the pointer
  // nears the island (a floating window only: a tiled one has no size of its own to
  // give), and goes back to its size when you let go anywhere else.
  property var dragWin: null            // { address, w, h, floating }
  property real dragScale: 0            // how far along the pull the window is shrunk (0 none, 1 all)
  // A tiled window has no size of its own to give, so it is floated while it is pulled
  // toward the island and tiled again if you let go anywhere else.
  readonly property bool shrinkTiled: setting("shrinkTiled", true) === true
  property bool forcedFloat: false
  property bool dragShrunk: false
  SafeProcess {
    id: dragWinRead
    command: Model.bounded(["hyprctl", "activewindow", "-j"], 4, 16384)
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var w = JSON.parse(Model.capped(text, 16384))
          if (w && root.validAddress(w.address) && w.size)
            // Read again later for its floating state; the first size is the true one.
            // The window is the one under the pointer when the drag began; a focus change
            // mid-drag must not move the target.
            if (root.dragWin) { if (root.dragWin.address === String(w.address)) root.dragWin.floating = w.floating === true }
            else root.dragWin = { address: String(w.address), cls: Model.clip(String(w.class || ""), 28), title: Model.clip(String(w.title || ""), 80), ws: String(w.workspace && w.workspace.name || ""), mon: Number(w.monitor), w: Number(w.size[0]), h: Number(w.size[1]), floating: w.floating === true }
        } catch (e) { root.dragWin = null }
      }
    }
  }
  // Resizes go one at a time, newest last: separate processes can finish out of order
  // and leave the window at an old size.
  property var resizeNext: null
  SafeProcess {
    id: resizeProc
    onExited: { if (root.resizeNext) { var n = root.resizeNext; root.resizeNext = null; root.dockResizeNow(n) } }
  }
  function dockResizeNow(n) {
    resizeProc.command = Model.bounded(["hyprctl", "dispatch", "hl.dsp.window.resize({ x = " + Math.round(n.w) + ", y = " + Math.round(n.h) + ", exact = true, window = \"address:" + n.address + "\" })"], 5, 0)
    resizeProc.running = true
  }
  function dockResize(address, w, h) {
    if (!validAddress(address)) return
    var n = { address: address, w: w, h: h }
    if (resizeProc.running) resizeNext = n
    else dockResizeNow(n)
  }
  // pull: 0 where the drag began, 1 on the island. The window goes from its own size
  // to (tw, th), the shape of the drop area, with a fast start: the first move upward
  // already makes it visibly smaller.
  property real pendingPull: 0
  property real pullW: 0
  property real pullH: 0
  function dockShrink(pull, tw, th) {
    pendingPull = Math.max(0, Math.min(1, Number(pull) || 0))
    pullW = tw
    pullH = th
    if (!shrinkTimer.running && dockDragging) shrinkTimer.start()
  }
  Timer {
    id: shrinkTimer
    interval: 33
    repeat: true
    onTriggered: {
      if (!root.dockDragging || !root.dragWin) { stop(); return }
      if (!root.dragWin.floating && !dragWinRead.running && root.pendingPull > 0.01) dragWinRead.running = true
      if (Math.abs(root.pendingPull - root.dragScale) < 0.008) return
      root.dragScale = root.pendingPull
      root.dragShrunk = root.dragScale > 0.004
      if (root.shrinkTiled && !root.dragWin.floating && root.dragScale > 0.03) {
        root.dragWin.floating = true
        root.forcedFloat = true
        root.fire(["hyprctl", "dispatch", "hl.dsp.window.float({ action = \"enable\", window = \"address:" + root.dragWin.address + "\" })"], 5)
      }
      var e = 1 - Math.pow(1 - root.dragScale, 2.6)
      var W = root.dragWin.w, H = root.dragWin.h
      var tw = Math.min(W, Math.max(60, root.pullW)), th = Math.min(H, Math.max(40, root.pullH))
      var nw = W + (tw - W) * e, nh = H + (th - H) * e
      if (root.dragWin.floating && W >= 160 && H >= 90) root.dockResize(root.dragWin.address, nw, nh)
    }
  }
  // Give a window its shape back: re-tile one we floated, else its own size.
  function dockReturnShape(address, tiled, w, h) {
    if (!validAddress(address)) return
    if (tiled) root.fire(["hyprctl", "dispatch", "hl.dsp.window.float({ action = \"disable\", window = \"address:" + address + "\" })"], 5)
    else if (w > 0 && h > 0) dockResize(address, w, h)
  }
  function dockUnshrink() {
    if (dragShrunk && dragWin) dockReturnShape(dragWin.address, forcedFloat, dragWin.w, dragWin.h)
    forcedFloat = false
    dragShrunk = false
    dragScale = 0
    pendingPull = 0
  }
  // A drag that never reports its release must not leave a window small.
  Timer { interval: 10500; running: root.dockDragging; onTriggered: { root.dockEnd(); root.dockUnshrink() } }
  // One short-lived loop for the length of a drag (the deadline ends it if the
  // release is ever missed), instead of a poll that runs all day.
  SafeProcess {
    id: dragPoll
    // No Model.bounded here: its `head` holds output back in a 4 KB buffer, and a
    // drag needs every line at once. The deadline alone ends the loop.
    command: ["/usr/bin/timeout", "-k", "2", "10", "/usr/bin/bash", "-c", "while :; do /usr/bin/hyprctl cursorpos; /usr/bin/sleep 0.03; done"]
    stdout: SplitParser {
      onRead: function(line) {
        var m = /^(-?\d+), (-?\d+)$/.exec(String(line).trim())
        if (m) { root.dockPointer = Qt.point(Number(m[1]), Number(m[2])); if (root.dockOrigin.x < -9000) root.dockOrigin = root.dockPointer }
      }
    }
  }
  function dockHas(address) { for (var i = 0; i < docked.length; i++) if (docked[i].address === address) return true; return false }
  function dockAdd(entry) { docked = docked.filter(function(d) { return d.address !== entry.address }).concat([entry]) }
  function dockDrop(address) { docked = docked.filter(function(d) { return d.address !== address }) }
  function validAddress(a) { return /^0x[0-9a-f]{4,16}$/.test(String(a)) }
  // Windows move by address; the address always comes from hyprctl, and is
  // checked here anyway because it ends up inside a Lua string.
  function dockMove(address, workspace, follow) {
    if (!validAddress(address) || !/^(special:island|[A-Za-z0-9_:. -]{1,40})$/.test(String(workspace))) return
    root.fire(["hyprctl", "dispatch", "hl.dsp.window.move({ workspace = \"" + workspace + "\", follow = " + (follow ? "true" : "false") + ", window = \"address:" + address + "\" })"], 5)
    if (workspace === "special:island") dockHideSpecial()
  }
  // Moving a window to special:island can leave that workspace showing, and a shown
  // special workspace dims everything in front of it (decoration:dim_special), the island
  // included. Hide it again, on whichever monitor it opened; it is a toggle, so look first.
  readonly property string hideSpecialScript: "for i in 1 2 3; do n=$(/usr/bin/hyprctl monitors -j | /usr/bin/jq -r '[.[]|select(.specialWorkspace.name==\"special:island\")]|length'); [ \"$n\" = \"0\" ] && break; /usr/bin/hyprctl dispatch 'hl.dsp.workspace.toggle_special(\"island\")' >/dev/null; sleep 0.25; done"
  function dockHideSpecial() { root.fire(["bash", "-c", root.hideSpecialScript], 8) }
  function dockFocus(address) {
    if (!validAddress(address)) return
    root.fire(["hyprctl", "dispatch", "hl.dsp.focus({ window = \"address:" + address + "\" })"], 5)
  }
  function dockRestoreLast() {
    if (docked.length > 0) dockRestoreRequested(docked[docked.length - 1].address)
  }
  // The list lives in memory; a shell restart must not strand a window on the
  // special workspace, so rebuild it from Hyprland once the shell is up. Windows
  // found this way have no picture, so they come back without the flight.
  Timer { interval: 4000; running: true; onTriggered: { dockScan.running = true; root.dockHideSpecial() } }
  SafeProcess {
    id: dockScan
    command: Model.bounded(["hyprctl", "clients", "-j"], 5, 262144)
    stdout: StdioCollector {
      onStreamFinished: {
        var list = []
        try { list = JSON.parse(Model.capped(text, 262144)) || [] } catch (e) { return }
        for (var i = 0; i < list.length; i++) {
          var c = list[i]
          if (!c || !c.workspace || c.workspace.name !== "special:island" || !root.validAddress(c.address) || root.dockHas(c.address)) continue
          root.dockAdd({ address: String(c.address), cls: Model.clip(String(c.class || ""), 60), title: Model.clip(String(c.title || ""), 80),
            rect: { x: 0, y: 0, w: Number(c.size && c.size[0]) || 800, h: Number(c.size && c.size[1]) || 600 }, ws: "1", snap: null })
        }
      }
    }
  }
  // A window closed while it waited here is not coming back.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event) return
      var name = String(event.name)
      // The special workspace showing makes the island gray and see-through: hide it
      // the moment Hyprland says it opened, however it got there.
      if (name === "activespecial" && /^special:island,/.test(String(event.data || ""))) { root.dockHideSpecial(); return }
      if (name !== "closewindow") return
      var a = "0x" + String(event.data || "").trim()
      if (root.dockHas(a)) root.dockDrop(a)
    }
  }

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
  readonly property var budsModeGlyphs: ({ smart: "", anc: "", transparency: "", vocal: "", off: "" })
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
        root.pushActivity({ kind: "alert", source: "buds-mode", icon: root.budsModeGlyphs[mode] || "", tint: mode === "off" ? "secondary" : "blue",
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
        root.pushActivity({ kind: "alert", source: "phone-link", icon: "", tint: "green", title: ev.model || root.phoneName,
          value: ev.transport === "usb" ? "USB" : "Wi-Fi", duration: 2400 })
      else if (ev.kind === "disconnected")
        root.pushActivity({ kind: "alert", source: "phone-link", icon: "", tint: "secondary", title: root.phoneName, value: "Disconnected", duration: 2000 })
      else if (ev.kind === "callEnded")
        root.pushActivity({ kind: "alert", source: "call", icon: "", tint: "red", title: root.callTitle(ev),
          value: ev.activeSince > 0 ? Model.formatTime(Date.now() / 1000 - ev.activeSince) : "Call Ended", duration: 2600 })
      else if (ev.kind === "missedCall")
        root.pushActivity({ kind: "alert", source: "call", icon: "", tint: "red", title: ev.name || ev.number || "Unknown", value: "Missed Call", duration: 5000 })
      else if (ev.kind === "nearby") {
        var b = root.phone.pstate && root.phone.pstate.battery ? root.phone.pstate.battery.level : -1
        root.pushActivity({ kind: "alert", source: "phone-link", icon: "", tint: "blue", title: ev.name || root.phoneName,
          value: b >= 0 ? b + "%" : "Nearby", duration: 2400 })
      }
      else if (ev.kind === "hotspot")
        root.pushActivity({ kind: "alert", source: "hotspot", icon: "", tint: ev.on ? "green" : "secondary", title: "Hotspot",
          value: ev.on ? "Connected" : "Off", duration: 2200 })
      else if (ev.kind === "sms") {
        var text = String(ev.body || "")
        var dup = root.seenMessage(text, Model.otpCode(text))
        if (root.showNotifications && !root.phoneMuted && !dup)
          root.pushActivity({ kind: "notification", source: "sms", file: "", app: "Messages · " + root.phoneName,
            title: ev.name || (ev.addresses || []).join(", "), body: text, image: "",
            urgent: false, duration: 6000, sms: ev })
      }
      else if (ev.kind === "error")
        root.pushActivity({ kind: "alert", source: "phone-error", icon: "", tint: "orange", title: String(ev.message || "Phone").slice(0, 60), value: "", duration: 3500 })
    }
  }

  // ------------------------------------------------------------ phone battery
  // The S24's charge, from phoned (adb / KDE Connect): a pill when it starts or stops charging,
  // and one warning as it drops to 20 %.
  readonly property int phoneBatLevel: root.phone && root.phone.pstate && root.phone.pstate.battery ? Number(root.phone.pstate.battery.level) : -1
  readonly property bool phoneBatCharging: !!(root.phone && root.phone.pstate && root.phone.pstate.battery && root.phone.pstate.battery.charging)
  property int phoneBatPrev: -1
  onPhoneBatChargingChanged: {
    if (!root.settled || root.phoneMuted || root.phoneBatLevel < 0) return
    root.pushActivity({ kind: "alert", source: "phone-battery", icon: root.phoneBatCharging ? root.glyphs.charging : root.glyphs.batteryAlert, tint: root.phoneBatCharging ? "green" : "secondary",
      title: root.phoneName, value: (root.phoneBatCharging ? "Charging " : "") + root.phoneBatLevel + "%", duration: 2400 })
  }
  onPhoneBatLevelChanged: {
    var was = root.phoneBatPrev
    root.phoneBatPrev = root.phoneBatLevel
    if (!root.settled || root.phoneMuted || root.phoneBatCharging) return
    if (root.phoneBatLevel >= 0 && root.phoneBatLevel <= 20 && was > 20)
      root.pushActivity({ kind: "alert", source: "phone-battery", icon: root.glyphs.batteryAlert, tint: "orange",
        title: root.phoneName, value: "Low battery " + root.phoneBatLevel + "%", duration: 4000 })
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
      // Virtual numbers (match ~/.local/bin/ws-go): MSI workspaces first, then the Tab, then the laptop.
      var items = []
      var list = Hyprland.workspaces ? Hyprland.workspaces.values : []
      function rank(w) { var m = w.monitor ? String(w.monitor.name) : ""; return m === "TAB" ? 1 : m.indexOf("eDP") === 0 ? 2 : 0 }
      for (var i = 0; i < list.length; i++) if (list[i] && list[i].id > 0) items.push({ id: list[i].id, r: rank(list[i]) })
      items.sort(function(a, b) { return a.r - b.r || a.id - b.id })
      var pos = 0
      var dots = items.map(function(it, k) { if (it.id === ws.id) pos = k + 1; return it.id === ws.id ? "●" : "○" }).join(" ")
      pushActivity({ kind: "alert", source: "workspace", icon: "", tint: "white", title: String(pos || ws.id), value: dots, duration: 1100 })
    }
    lastWorkspace = ws.id
  }

  // ------------------------------------------------------------ lyrics
  // Synced lyrics for the playing track from lrclib.net (onlineExtras only).
  property var lyrics: []
  readonly property string lyricLine: lyrics.length ? Model.lyricAt(lyrics, trackPosition) : ""
  readonly property string lyricsKey: onlineExtras && trackTitle !== "" && trackArtist !== "" ? trackArtist + "\u0000" + trackTitle : ""
  onLyricsKeyChanged: {
    lyrics = []
    lyricsFetch.running = false
    if (lyricsKey !== "") lyricsDelay.restart()
  }
  // Skipping through tracks shouldn't fire a lookup per track.
  Timer { id: lyricsDelay; interval: 1500; onTriggered: if (root.lyricsKey !== "") lyricsFetch.running = true }
  SafeProcess {
    id: lyricsFetch
    command: Model.bounded(["curl", "-q", "-fsG", "--proto", "=https", "--max-time", "8", "https://lrclib.net/api/get",
      "--data-urlencode", "artist_name=" + Model.clip(root.trackArtist, 200),
      "--data-urlencode", "track_name=" + Model.clip(root.trackTitle, 200)]
      .concat(root.trackLength > 0 ? ["--data-urlencode", "duration=" + Math.round(root.trackLength)] : []), 12, 262144)
    stdout: StdioCollector {
      onStreamFinished: {
        var t = Model.capped(text, 262144)
        if (!t) return
        try { root.lyrics = Model.parseLrc(JSON.parse(t).syncedLyrics) } catch (e) { root.lyrics = [] }
      }
    }
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
              time: Number(d.timestamp) || 0, urgent: Number(d.urgency) === 2, execArgv: String(d.execArgv || ""),
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
  // ------------------------------------------------------------ recent activity
  // What the island did lately, newest first, for the History view: timers
  // and alarms that went off, calls, recordings, stopwatch runs, songs.
  // ponytail: in memory only, so a shell restart empties it; keep it in the
  // private run directory if that ever matters.
  property var recent: []
  function logRecent(icon, tint, title, value, image) {
    var e = { icon: Model.clip(icon, 16), tint: String(tint || "white"), title: Model.clip(title, 200),
      value: Model.clip(value, 120), time: Date.now(), image: String(image || "") }
    var next = recent.slice(0, 39)
    next.unshift(e)
    recent = next
  }
  function removeRecent(e) { recent = recent.filter(function(r) { return r !== e }) }
  function clearRecent() { recent = [] }
  // A song counts once it has been playing for a few seconds, and only once
  // in a row, so skipping through a playlist doesn't flood the list.
  Timer {
    id: songLog
    interval: 8000
    onTriggered: {
      if (!root.isPlaying || root.trackTitle === "") return
      var top = root.recent.length > 0 ? root.recent[0] : null
      if (top && top.title === root.trackTitle) return
      root.logRecent(root.glyphs.music, "pink", root.trackTitle, root.trackArtist, root.artLocal)
    }
  }
  onTrackTitleChanged: if (trackTitle !== "") songLog.restart()
  readonly property bool showHistory: setting("showHistory", true) === true
  readonly property bool swipeToTuck: setting("swipeToTuck", false) === true
  readonly property bool reserveSpace: setting("reserveSpace", false) === true
  readonly property int reserveGap: Math.max(0, Math.min(24, Number(setting("reserveGap", 4))))
  // How wide a notification opens the island (px); History matches it.
  readonly property int notificationWidth: Math.max(300, Math.min(700, Number(setting("notificationWidth", 340))))

  // ------------------------------------------------ call notes
  // One Markdown file per call, named by when it connected: the notes you
  // write and, with callTranscript on, the transcript land in the same file.
  // Text goes in as arguments, never through the shell.
  readonly property string callNotesDir: Quickshell.env("HOME") + "/.local/share/omarchy/call-notes"
  function callNotePath(startMs) {
    return callNotesDir + "/" + Qt.formatDateTime(new Date(startMs), "yyyy-MM-dd_HH-mm-ss") + ".md"
  }
  function oneLine(v, max) { return Model.clip(String(v || "").replace(/[\r\n]+/g, " ").trim(), max) }
  function callNoteHeader(name, number, startMs, duration) {
    name = oneLine(name, 120); number = oneLine(number, 40)
    return "# Call with " + (name || number || "Unknown") + "\n\n" +
      "- Name: " + name + "\n" +
      "- Number: " + number + "\n" +
      "- Time: " + Qt.formatDateTime(new Date(startMs), "dddd d MMMM yyyy, HH:mm") + "\n" +
      (duration > 0 ? "- Duration: " + Model.formatTime(duration) + "\n" : "")
  }
  // Appends under a lock, creating the file with its header first if needed.
  function appendCallNote(path, header, section) {
    root.fire(["bash", "-c", "umask 077; d=$(/usr/bin/dirname -- \"$1\"); /usr/bin/mkdir -p -- \"$d\" || exit 1; " +
      "exec 9>>\"$d/.lock\"; /usr/bin/flock 9; [ -e \"$1\" ] || printf '%s' \"$2\" > \"$1\"; printf '%s' \"$3\" >> \"$1\"",
      "note", path, header, section], 10)
  }
  function saveCallNote(n) {
    var start = Number(n.time) || Date.now()
    var body = Model.clip(String(n.notes || "").trim(), 20000)
    if (body === "") return
    appendCallNote(callNotePath(start), callNoteHeader(n.name, n.number, start, n.duration), "\n## Notes\n\n" + body + "\n")
    logRecent("\uE2CE", "blue", "Call note", oneLine(n.name, 120) || oneLine(n.number, 40) || "Unknown")
  }

  // Transcripts: the call view's Transcript button records both sides until
  // pressed again or the call ends, then whisper-cli writes the conversation
  // into the call's file (call-transcript.sh). The button only shows with
  // callTranscript on: recording a call can need the other person's consent.
  readonly property bool callTranscript: setting("callTranscript", false) === true
  readonly property string whisperModel: String(setting("whisperModel",
    Quickshell.env("HOME") + "/.local/share/whisper-models/ggml-small.en.bin"))
  readonly property string transcriptScript: String(Qt.resolvedUrl("call-transcript.sh")).replace(/^file:\/\//, "")
  property var recordingCall: null
  readonly property real connectedSince: currentCall && currentCall.state === "active" ? Number(currentCall.activeSince) || 0 : 0
  // The call it belongs to ended (or another one took over): finish it.
  onConnectedSinceChanged: if (recordingCall && recordingCall.since !== connectedSince) finishTranscript()
  function startTranscript() {
    if (!callTranscript || recordingCall || connectedSince <= 0) return
    recordingCall = { since: connectedSince, name: String(currentCall.name || ""), number: String(currentCall.number || "") }
    root.launch(["bash", root.transcriptScript, "start"])
  }
  function toggleTranscript() { if (recordingCall) finishTranscript(); else startTranscript() }
  function finishTranscript() {
    var c = recordingCall
    recordingCall = null
    if (!c) return
    var start = c.since * 1000
    root.launch(["bash", root.transcriptScript, "stop", callNotePath(start),
      callNoteHeader(c.name, c.number, start, Date.now() / 1000 - c.since), root.whisperModel])
    logRecent("\uE2CE", "blue", "Call transcript", c.name || c.number || "Unknown")
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
  // Off: the island only opens for Now Playing, never to the clock/calendar card.
  readonly property bool showHome: setting("showHome", true) === true

  // ------------------------------------------------------------ expanded (shared across windows)
  // Only the most recent screen to open wins; another screen opening closes it.
  property var expandedWindow: null
  signal collapseAll()

  // ------------------------------------------------------------ bar footprint
  // The bar spacer reads this so bar widgets flow around the notch the way
  // the macOS menu bar flows around the camera housing.
  // The window on the focused screen reports its resting width here.
  property int restingWidth: notchWidth
  // iOS minimal: round, or an oval when the content is wider than a glyph (the stopwatch time).
  readonly property int bubbleWidth: secondLive === "stopwatch" ? Math.min(45, Math.round(notchHeight * 1.25)) : notchHeight
  readonly property int barFootprint: restingWidth + (secondLive !== "" ? bubbleWidth + 8 : 0) * 2

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
  IpcHandler {
    target: "island"
    function state(): string {
      return JSON.stringify({
        live: root.live, second: root.secondLive,
        activity: root.activity ? { kind: root.activity.kind, source: String(root.activity.source).indexOf("ipc-") === 0 ? "ipc" : root.activity.source } : null,
        queued: root.queue.length,
        media: { playing: root.isPlaying, player: root.playerName, lyrics: root.lyrics.length },
        timerLeft: Math.round(root.timerLeft), stopwatch: Math.floor(root.stopwatchElapsed), alarm: root.alarmAt > 0 ? Model.clockText(root.alarmAt) : "", alarmRinging: root.alarmRinging, tucked: Object.keys(root.tucked), recording: root.recording, micInUse: root.micInUse, cameraInUse: root.cameraInUse,
        battery: root.batteryPercent, charging: root.charging, dnd: root.dnd,
        phone: { mirrored: root.phoneOnScreen, muted: root.phoneMuted },
        monitor: root.monitor, palette: root.paletteName, reduceMotion: root.reduceMotion, font: root.textFont, notchHeight: root.notchHeight
      })
    }
    function ping(): string { return "ok" }
    function expand(): string { root.expandRequested(); return "ok" }
    function history(): string { root.historyRequested(); return "ok" }
    // Same as one scroll notch on the island: next / previous activity,
    // and past the last one, the history.
    function next(): string { root.stepRequested(1); return "ok" }
    function prev(): string { root.stepRequested(-1); return "ok" }
    // A call note form, prefilled from the current call if there is one.
    function callNotes(): string { root.callNotesRequested(); return "ok" }
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
    function phoneDex(): string { if (!root.phone) return "no-taildroid"; root.phone.openDex(); return "ok" }
    function timer(seconds: string): string {
      var n = Number(seconds)
      if (!isFinite(n) || n < 1 || n > 86400) return "bad-seconds"
      root.startTimer(n)
      return "ok"
    }
    function timerCancel(): string { root.cancelTimer(); return "ok" }
    function aiActivity(text: string): string {
      root.aiLabel = "Phone"
      root.aiText = Model.clip(text, 48)
      root.aiUntil = Date.now() + 8000
      root.now = new Date()
      return "ok"
    }
    function stopwatch(): string { root.toggleStopwatch(); return "ok" }
    function stopwatchReset(): string { root.resetStopwatch(); return "ok" }
    function alarm(hhmm: string): string { return root.setAlarm(hhmm) ? "ok" : "bad-time" }
    function alarmCancel(): string { root.cancelAlarm(); return "ok" }
    function alarmStop(): string { root.stopAlarm(); return "ok" }
    function tuck(): string { return root.tuckLive() ? "ok" : "not-tuckable" }
    // Super + mouse drag, wired in bindings.lua: pointer tracking while it lasts,
    // and the drop that minimises the window if it landed on the island.
    function dockDragStart(): string { root.dockStart(); return "ok" }
    function dockDragDrop(): string { root.dockDropRequested(); return "ok" }
    // The same flight for the focused window, without a drag: bind it to a key.
    function dockMinimize(): string { root.dockMinimizeRequested(); return "ok" }
    function dockRestore(address: string): string {
      if (address === "") { root.dockRestoreLast(); return root.dockCount > 0 ? "ok" : "empty" }
      if (!root.dockHas(address)) return "unknown"
      root.dockRestoreRequested(address)
      return "ok"
    }
    function alarmSnooze(): string { return root.snoozeAlarm() ? "ok" : "not-ringing" }
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
        title: Model.clip(title, 120), body: Model.clip(body, 400), image: "", urgent: false,
        duration: 5000 })
      return "ok"
    }
    // A one-time code read from an SMS: from (the sender), the code, and how many minutes it lasts (0: not said).
    function otp(from: string, code: string, minutes: string): string {
      if (!/^\d{4,8}$/.test(code)) return "bad code"
      if (root.seenMessage("", code)) return "shown"   // the island already had it from the SMS itself
      root.pushActivity({ kind: "notification", source: "ipc-otp", file: "", app: "One-time code",
        title: Model.clip(from, 60), body: "", code: code, minutes: Model.clamp(Number(minutes) || 0, 0, 60),
        image: "", urgent: false, sms: true, duration: 20000 })
      return "ok"
    }
  }
  signal expandRequested()
  signal historyRequested()
  signal stepRequested(int dir)
  signal callNotesRequested()

  // The first Service to start is the island; the bar widget finds it here.
  Item {
    Component.onCompleted: if (!Registry.current) Registry.current = root
    Component.onDestruction: if (Registry.current === root) Registry.current = null
  }

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
