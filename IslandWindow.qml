import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "IslandModel.js" as Model

// One notch per monitor. A full-width, transparent overlay layer whose input
// region is exactly the island, so the desktop and the bar underneath stay
// clickable everywhere else.
PanelWindow {
  id: win

  property var service: null
  // Set once by the Variants delegate; comparing names (not win.screen) keeps
  // hiding the window from feeding back into this check.
  property string screenName: ""
  readonly property var s: service

  anchors {
    top: true
    left: true
    right: true
  }
  // Room for the largest island plus its drop shadow.
  implicitHeight: s.notchHeight + 600 + 56
  color: "transparent"
  surfaceFormat.opaque: false
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "omarchy-dynamic-island"
  WlrLayershell.layer: WlrLayer.Overlay
  // The Control Center takes the keyboard while it's open (Esc, the Wi-Fi
  // password, Taildroid pairing), and so does the expanded island when it
  // was opened from the keyboard (`island expand`). Opened by hover it
  // leaves typing alone.
  property bool keyExpanded: false
  readonly property bool keyHeld: controlsOpen || (expanded && keyExpanded) || (callOpen && callView.notesOpen)
  WlrLayershell.keyboardFocus: keyHeld ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
  mask: Region {
    item: hit
    regions: [ Region { item: bubbleHit } ]
  }

  // With monitor "focused" only the focused screen shows the island, so an
  // extended desktop doesn't get two of them.
  readonly property bool onThisScreen: {
    if (s.monitor === "external") return win.screenName === s.preferredScreen
    if (s.monitor !== "focused") return true
    var f = Hyprland.focusedMonitor
    return !f || win.screenName === "" || f.name === win.screenName
  }
  visible: onThisScreen
  onOnThisScreenChanged: if (!onThisScreen) { hovered = false; setExpanded(false); closeControls() }
  // Null when controlCenter is off: then it is never built at all.
  readonly property var cc: ccLoader.item
  // Which window answers a keyboard shortcut: the one showing the island
  // (external mode), otherwise the one on the focused monitor.
  function isTarget() {
    if (s.monitor === "external") return onThisScreen
    var f = Hyprland.focusedMonitor
    return !f || f.name === screenName
  }

  // ---------------------------------------------------------------- state
  readonly property var hyprMonitor: Hyprland.monitorFor(win.screen)
  readonly property bool fullscreen: hyprMonitor && hyprMonitor.activeWorkspace
    ? !!hyprMonitor.activeWorkspace.hasFullscreen : false

  property bool hovered: false
  property bool expanded: false
  property bool controlsOpen: false
  property bool historyOpen: false
  property bool callOpen: false
  readonly property alias callView: callView
  readonly property var t: s.activity

  // When the island last changed shape. A notification that grows under a
  // pointer already resting at the top is not a hover, and a click that lands
  // as it pops in is not meant for it.
  property double modeSince: 0
  onModeChanged: modeSince = Date.now()
  readonly property string mode: {
    if (controlsOpen) return "controls"
    // A ringing phone beats everything else, like iOS's incoming-call banner.
    if (s.ringingCall) return "incoming"
    if (callOpen) return "callview"
    if (historyOpen) return "history"
    // A new notification briefly takes over the expanded island; `expanded`
    // stays set, so the player/home view springs back once it's done.
    if (t && t.kind === "notification") return "notification"
    if (expanded && (s.expandedPages.length > 0 || s.showHome)) return "expanded"
    if (t) return t.kind
    if (fullscreen && s.hideInFullscreen && !hovered) return "hidden"
    if (s.live !== "") return "compact"
    // A privacy dot nobody can see is not an indicator: mic or camera capture
    // brings the pill back even when the island is set to hide while idle.
    return s.showWhenIdle || hovered || s.micInUse || s.cameraInUse ? "idle" : "hidden"
  }

  // Views keep drawing the last payload of their kind while they fade out.
  property var lastAlert: ({ icon: "", tint: "white", title: "", value: "" })
  property var lastHud: ({ icon: "", tint: "white", percent: 0, value: "" })
  property var lastNotif: ({ app: "", title: "", body: "", image: "", urgent: false })
  onTChanged: {
    if (!t) return
    if (t.kind === "alert") lastAlert = t
    else if (t.kind === "hud") lastHud = t
    else if (t.kind === "notification") lastNotif = t
  }

  TextMetrics { id: alertTitleMetrics; font.family: s.textFont; font.pixelSize: Model.TYPE.subhead; font.weight: Font.DemiBold; text: win.lastAlert.title || "" }
  TextMetrics { id: alertValueMetrics; font.family: s.textFont; font.pixelSize: Model.TYPE.subhead; font.weight: Font.DemiBold; text: win.lastAlert.value || "" }
  // ---------------------------------------------------------------- symmetric compact layout
  // Leading and trailing views hug the ends with the same concentric inset,
  // their slots are equal width, and the clock sits dead center — so the
  // island always reads as balanced whatever it shows.
  TextMetrics { id: clockMetrics; font.family: s.textFont; font.pixelSize: s.notchHeight >= 28 ? 14 : 13; font.weight: Font.DemiBold; font.features: { "tnum": 1 }; text: s.clockText }
  // Timer, recording, call and phone all wear the same compact face: a tinted
  // mark at the leading edge, a tinted read-out at the trailing one. Media is
  // the exception - artwork and a waveform - so it stays written out below.
  component CompactActivity: Reveal {
    reduced: win.s.reduceMotion
    id: act
    property string kind: ""
    property string tone: ""
    property string glyph: ""           // empty: the recording light, a plain dot
    property string trail: ""
    property real trailOpacity: 1
    property bool pulsing: false
    property int pulseMs: 700

    shown: win.mode === "compact" && win.s.live === act.kind
    width: win.geometryFor("compact").w
    height: win.s.notchHeight
    anchors.horizontalCenter: parent.horizontalCenter
    inDelay: 60

    Text {
      textFormat: Text.PlainText
      id: lead
      visible: act.glyph !== ""
      x: win.edge + 1
      anchors.verticalCenter: parent.verticalCenter
      text: act.glyph
      font.family: win.s.iconFont
      font.pixelSize: Model.TYPE.callout
      color: win.s.tint(act.tone)
    }
    Rectangle {
      id: leadDot
      visible: act.glyph === ""
      x: win.edge + 4
      anchors.verticalCenter: parent.verticalCenter
      width: 9
      height: 9
      radius: 4.5
      color: win.s.tint(act.tone)
    }
    // A waiting call and a running recording both blink their mark. Only
    // while shown: a running animation redraws the window every frame.
    SequentialAnimation {
      running: act.pulsing && act.shown
      loops: Animation.Infinite
      onStopped: { lead.opacity = 1; leadDot.opacity = 1 }
      NumberAnimation { targets: [lead, leadDot]; property: "opacity"; to: 0.35; duration: act.pulseMs; easing.type: Easing.InOutSine }
      NumberAnimation { targets: [lead, leadDot]; property: "opacity"; to: 1; duration: act.pulseMs; easing.type: Easing.InOutSine }
    }
    Text {
      textFormat: Text.PlainText
      anchors.right: parent.right
      anchors.rightMargin: win.edge + 4
      anchors.verticalCenter: parent.verticalCenter
      text: act.trail
      font: trailMetrics.font
      color: win.s.tint(act.tone)
      opacity: act.trailOpacity
    }
  }

  TextMetrics { id: trailMetrics; font.family: s.textFont; font.pixelSize: s.notchHeight >= 28 ? 14 : 13; font.weight: Font.DemiBold; font.features: { "tnum": 1 }; text: win.trailText }
  readonly property int edge: Math.max(4, Math.round((s.notchHeight - 16) / 2))
  readonly property string trailText: s.live === "call" ? s.callElapsed(s.currentCall)
    : s.live === "timer" ? Model.formatTime(Math.ceil(s.timerLeft))
    : s.live === "stopwatch" ? Model.formatTime(s.stopwatchElapsed)
    : s.live === "ai" ? s.aiLabel
    : s.live === "recording" ? (s.now, Model.formatTime((Date.now() - s.recordingSince) / 1000))
    : s.live === "phone" ? (s.now, Model.formatTime((Date.now() - s.phoneSince) / 1000))
    : ""
  readonly property int artSize: s.notchHeight - 8
  readonly property int leadWidth: s.live === "media" ? artSize : s.live === "recording" ? 9 : 16
  readonly property int trailWidth: s.live === "media" ? 22 : Math.ceil(trailMetrics.advanceWidth)
  // Rounded up to 8px steps so the width doesn't twitch every second as digits change.
  readonly property int slot: Math.ceil(Math.max(leadWidth, trailWidth) / 8) * 8
  readonly property int clockWidth: s.showClock ? Math.ceil(clockMetrics.advanceWidth) : 36
  readonly property int compactContentWidth: 2 * (edge + slot) + 2 * 12 + clockWidth
  readonly property int idleContentWidth: s.showClock ? clockWidth + 2 * (s.notchHeight / 2 + 8) : 0
  onBwChanged: if (onThisScreen && (mode === "idle" || mode === "compact") && !hovered) s.restingWidth = Math.round(geometryFor(mode).w)

  readonly property int alertContentWidth: 18 + 20 + 10 + Math.ceil(alertTitleMetrics.advanceWidth) + 36 + Math.ceil(alertValueMetrics.advanceWidth) + 20

  // ---------------------------------------------------------------- geometry
  function geometryFor(m) {
    if (m === "controls")
      // The body has to grow with the page, or a wide one spills off the pill.
      return { w: Math.max(120, cc ? cc.preferredWidth : 0), h: Math.max(120, cc ? cc.preferredHeight : 0), rb: 34, rt: 0 }
    if (m === "callview")
      return { w: callView.preferredWidth, h: callView.preferredHeight, rb: 34, rt: 0 }
    if (m === "history")
      return { w: historyView.preferredWidth, h: historyView.preferredHeight, rb: 34, rt: 0 }
    var content = m === "compact" ? compactContentWidth : m === "idle" ? idleContentWidth
      : m === "notification" ? s.notificationWidth : alertContentWidth
    return Model.geometry(m, s.notchWidth, s.notchHeight, content, s.appleSize && s.hasMedia)
  }
  readonly property var geom: {
    var g = geometryFor(mode)
    // Hover "breath": the notch swells slightly under the pointer, inviting
    // a click — the tactile cue macOS notch apps use in place of haptics.
    if (hovered && (mode === "idle" || mode === "compact"))
      return { w: g.w + 10, h: g.h, rb: g.rb, rt: 0 }
    return g
  }

  // Animated body geometry. Growing uses a bouncier spring (the island
  // "pops" open with a little overshoot); shrinking is more damped, so it
  // tucks back into the notch without wobbling.
  property real bw: 0
  property real bh: 0
  property real brb: 0
  property real brt: 0
  property bool growing: true
  function applyGeometry(animate) {
    var g = geom
    growing = g.w * g.h >= bw * bh
    if (!animate) {
      bwBehavior.enabled = false; bhBehavior.enabled = false; brbBehavior.enabled = false; brtBehavior.enabled = false
    }
    bw = g.w
    bh = g.h
    brb = g.rb
    brt = g.rt
    bwBehavior.enabled = true; bhBehavior.enabled = true; brbBehavior.enabled = true; brtBehavior.enabled = true
  }
  onGeomChanged: applyGeometry(true)
  Component.onCompleted: applyGeometry(false)

  // Reduce motion: the shape still morphs, but settles without a bounce.
  readonly property real springK: s.reduceMotion ? 7 : growing ? 3.3 : 4.4
  readonly property real springD: s.reduceMotion ? 1 : growing ? 0.33 : 0.42
  Behavior on bw { id: bwBehavior; SpringAnimation { spring: win.springK; damping: win.springD; epsilon: 0.25 } }
  Behavior on bh { id: bhBehavior; SpringAnimation { spring: win.springK * 1.08; damping: win.springD; epsilon: 0.25 } }
  Behavior on brb { id: brbBehavior; SpringAnimation { spring: win.springK; damping: win.s.reduceMotion ? 1 : 0.5; epsilon: 0.1 } }
  Behavior on brt { id: brtBehavior; SpringAnimation { spring: win.springK; damping: win.s.reduceMotion ? 1 : 0.5; epsilon: 0.1 } }

  // How far the island has grown past the bare notch; drives the shadow.
  readonly property real lift: Model.clamp((bh - s.notchHeight) / 60, 0, 1)

  // ---------------------------------------------------------------- behavior
  function openControls(page) {
    if (!cc) return
    if (!controlsOpen) {
      if (expanded) setExpanded(false)
      s.expandedWindow = win
      controlsOpen = true
    }
    cc.page = page || "main"
  }
  function closeControls() { controlsOpen = false }
  function openCall() {
    if (expanded) setExpanded(false)
    historyOpen = false
    s.expandedWindow = win
    callOpen = true
    pageIndex = Math.max(0, pageOf("call"))
  }
  // ---------------------------------------------------------------- room
  // reserveSpace: an invisible strip that keeps tiled windows clear of the
  // resting pill (it hangs below the bar), so nothing presses on its edge.
  // It only reserves space; it draws nothing and takes no input.
  PanelWindow {
    screen: win.screen
    visible: win.s.reserveSpace && win.onThisScreen && win.s.barPosition === "top"
    anchors { top: true; left: true; right: true }
    implicitHeight: 1
    color: "transparent"
    mask: Region {}
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: Math.max(0, win.s.islandTop + win.s.notchHeight + win.s.reserveGap - win.s.barHeight)
    WlrLayershell.namespace: "omarchy-dynamic-island-space"
    // Overlay, not Top: Hyprland arranges exclusive zones layer by layer,
    // so on Overlay the strip stacks under the bar instead of above it.
    WlrLayershell.layer: WlrLayer.Overlay
  }

  // ---------------------------------------------------------------- scroll feel
  // Each scroll step answers like a detent: the new activity slides in from
  // the scroll direction and settles with a small overshoot, and the island
  // gives a quick squish and springs back, the visual stand-in for the
  // iPhone's haptic tick.
  property real slideY: 0
  property real squish: 0
  property real slideDist: 0
  // Out, then in: the leaving activity slides off in the scroll direction
  // while it fades, the arriving one comes in from the other side and
  // settles with a small overshoot.
  SequentialAnimation {
    id: slideAnim
    NumberAnimation { target: win; property: "slideY"; to: -win.slideDist; duration: 120; easing.type: Easing.InQuad }
    PropertyAction { target: win; property: "slideY"; value: win.slideDist }
    NumberAnimation { target: win; property: "slideY"; to: 0; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.5 }
  }
  SequentialAnimation {
    id: squishAnim
    NumberAnimation { target: win; property: "squish"; to: 1; duration: 70; easing.type: Easing.OutQuad }
    SpringAnimation { target: win; property: "squish"; to: 0; spring: 5; damping: 0.22; epsilon: 0.002 }
  }
  function feelStep(dir) {
    if (s.reduceMotion) return
    slideAnim.stop()
    slideY = 0
    slideDist = dir * Math.max(12, bh * 0.6)
    slideAnim.start()
    squishAnim.restart()
  }

  // Vertical scrolling anywhere on the island (the pill, any open view, the
  // second bubble) lands here. One flick is one step: after a step the rest
  // of that gesture, touchpad inertia included, is spent, like an iPhone
  // detent, so a fast swipe doesn't skip three activities.
  property real wheelAccum: 0
  property real wheelQuietUntil: 0
  // Precision: a scroll only counts once the pointer has been on the island
  // for a moment (not a page scroll carried over as it slides past), and
  // only when it is clearly up or down, not a diagonal touchpad drift.
  property real hoverSince: 0
  readonly property int settleMs: 180
  function islandWheel(wheel) {
    var dy = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.pixelDelta.y * 4
    var dx = wheel.angleDelta.x !== 0 ? wheel.angleDelta.x : wheel.pixelDelta.x * 4
    if (dy === 0 || mode === "controls") return
    if (Math.abs(dy) < 2 * Math.abs(dx)) return
    if (Date.now() - hoverSince < settleMs) { wheelAccum = 0; return }
    // History scrolls its list; an up-scroll at the top closes it.
    if (mode === "history") { if (Date.now() >= wheelQuietUntil) historyView.wheel(dy); return }
    // Typing a call note: the notes box scrolls, the island stays put.
    if (mode === "callview" && callView.notesOpen) return
    var now = Date.now()
    if (now < wheelQuietUntil) { wheelQuietUntil = now + 180; return }
    if (s.showHistory) {
      if ((wheelAccum < 0) !== (dy < 0)) wheelAccum = 0
      wheelAccum += dy
      if (Math.abs(wheelAccum) < 120) return
      var dir = wheelAccum < 0 ? 1 : -1
      wheelAccum = 0
      wheelQuietUntil = now + 300
      dwellTimer.stop()
      scrollStep(dir)
      return
    }
    if (mode === "expanded" || mode === "hidden" || mode === "history" || mode === "callview") return
    // Scrolling says "adjust", not "open": hold off the hover-open.
    if (dwellTimer.running) dwellTimer.restart()
    wheelAccum += dy
    // Touchpads send many small deltas; step once per wheel notch.
    if (Math.abs(wheelAccum) >= 120) {
      s.scrollVolumeBy(wheelAccum)
      wheelAccum = 0
    }
  }

  // ---------------------------------------------------------------- pages
  // The opened island pages through everything running at full size:
  // music (one page per player), call, timer, stopwatch, recording, phone.
  property int pageIndex: 0
  readonly property var page: s.expandedPages.length > 0
    ? s.expandedPages[Math.max(0, Math.min(pageIndex, s.expandedPages.length - 1))] : null
  function pageOf(k) {
    var pages = s.expandedPages
    for (var i = 0; i < pages.length; i++) {
      if (pages[i].kind !== k) continue
      if (k !== "media" || !s.player || pages[i].key === Model.playerKey(s.player)) return i
    }
    return -1
  }
  function showPage(i) {
    var pg = s.expandedPages[i]
    if (!pg) return
    if (pg.kind === "media") s.pinnedPlayerKey = pg.key
    if (pg.kind !== "media" && pg.kind !== "call") s.pinnedLive = pg.kind
    if (pg.kind === "call") { if (expanded) setExpanded(false); s.expandedWindow = win; callOpen = true }
    else { callOpen = false; if (!expanded) setExpanded(true) }
    pageIndex = i
  }
  readonly property bool mediaPage: !page || page.kind === "media"
  // Up past the first page tucks the island back to its own size.
  function pageStep(dir) {
    var i = pageIndex + dir
    if (i < 0) { callOpen = false; setExpanded(false); feelStep(-1); return }
    if (i >= s.expandedPages.length) { openHistory(); feelStep(1); return }
    showPage(i)
    feelStep(dir)
  }

  // One scroll notch walks one list, both ways:
  //   pill -> the full page of what's in front -> the other full pages
  //   (music players, call, timer...) -> History,
  // and up retraces it to the pill. 1 = down, -1 = up.
  function scrollStep(dir) {
    if (mode === "history") {
      if (dir > 0) return
      historyOpen = false
      wheelQuietUntil = Date.now() + 300
      if (s.expandedPages.length > 0) showPage(s.expandedPages.length - 1)
      feelStep(-1)
      return
    }
    if (mode === "expanded" || mode === "callview") { pageStep(dir); return }
    // A passing alert, volume pill or notification steps aside for the scroll.
    if ((mode === "alert" || mode === "hud" || mode === "notification") && t && t.source !== "alarm-ring") s.finishActivity()
    if (dir < 0) return
    dwellTimer.stop()
    if (s.expandedPages.length > 0) showPage(Math.max(0, pageOf(s.live === "" ? "media" : s.live)))
    else openHistory()
    feelStep(1)
  }
  function openHistory() {
    if (!s.showHistory || historyOpen) return
    if (expanded) setExpanded(false)
    closeControls()
    s.expandedWindow = win
    historyOpen = true
  }
  // Tap outside the island to dismiss the Control Center, like iOS.
  // The grab starts a beat after opening: the surface first takes keyboard
  // focus, and a grab raced against that change is cleared immediately.
  property bool grabReady: false
  onControlsOpenChanged: s.controlsShown = controlsOpen
  onKeyHeldChanged: {
    grabReady = false
    if (keyHeld) grabDelay.restart()
  }
  Timer { id: grabDelay; interval: 250; onTriggered: win.grabReady = win.keyHeld }
  HyprlandFocusGrab {
    active: win.keyHeld && win.grabReady && win.visible
    windows: [win]
    // An unsaved call note stays open; Save or Cancel closes it.
    onCleared: { if (win.callOpen) return; win.closeControls(); win.setExpanded(false) }
  }

  function setExpanded(on) {
    if (!on) keyExpanded = false
    if (on === expanded) return
    expanded = on
    if (on) {
      s.expandedWindow = win
      s.positionWatchers++
      // Open on the page of whatever is in front.
      pageIndex = Math.max(0, pageOf(s.live === "" ? "media" : s.live))
    } else {
      s.positionWatchers = Math.max(0, s.positionWatchers - 1)
      s.pinnedPlayerKey = ""
    }
  }
  Connections {
    target: win.s
    function onExpandedWindowChanged() { if (win.s.expandedWindow !== win) { win.setExpanded(false); win.closeControls(); win.historyOpen = false; win.callOpen = false } }
    function onCollapseAll() { win.setExpanded(false); win.closeControls(); win.historyOpen = false; win.callOpen = false }
    function onControlsRequested(page) {
      if (win.isTarget()) {
        if (win.controlsOpen && win.cc && (page === "main" || page === win.cc.page)) win.closeControls()
        else win.openControls(page)
      }
    }
    function onCallNotesRequested() { if (win.isTarget()) { win.openCall(); win.callView.openNotes() } }
    function onStepRequested(dir) { if (win.isTarget()) win.scrollStep(dir) }
    function onHistoryRequested() { if (win.isTarget()) { if (win.historyOpen) win.historyOpen = false; else win.openHistory() } }
    function onExpandRequested() { if (win.isTarget()) { win.keyExpanded = true; win.setExpanded(true) } }
    function onRingingCallChanged() { if (win.s.ringingCall) win.setExpanded(false) }
  }
  Component.onDestruction: if (expanded) s.positionWatchers = Math.max(0, s.positionWatchers - 1)

  // The pointer has to rest on the notch for a moment before it opens, so
  // sweeping the cursor across the top of the screen doesn't trigger it.
  Timer {
    id: dwellTimer
    interval: win.s.hoverDelay
    onTriggered: if (win.hovered && (win.mode === "idle" || win.mode === "compact")) win.setExpanded(true)
  }
  Timer {
    id: leaveTimer
    interval: win.expanded || win.historyOpen ? 380 : 140
    onTriggered: {
      win.hovered = false
      if (win.t) win.s.holdActivity(false)
      if (!win.controlsOpen) win.setExpanded(false)
      win.historyOpen = false
      if (!callView.notesOpen) win.callOpen = false
    }
  }

  // Input only reaches this window inside the mask (the island), so hover
  // on the stage is hover on the island — including over its buttons.
  Item {
    id: stage
    anchors.fill: parent

    HoverHandler {
      id: hover
      // Hover-open only when the pointer rests: moving across the island
      // (on the way to a browser tab, say) keeps pushing the open back.
      property point restAt: Qt.point(0, 0)
      onPointChanged: {
        var p = point.position
        if (Math.abs(p.x - restAt.x) + Math.abs(p.y - restAt.y) < 6) return
        restAt = p
        if (dwellTimer.running) dwellTimer.restart()
      }
      onHoveredChanged: {
        if (hovered) {
          leaveTimer.stop()
          win.hovered = true
          win.hoverSince = Date.now()
          if (win.t && Date.now() - win.modeSince > 400) win.s.holdActivity(true)
          if (win.s.openOnHover && (win.mode === "idle" || win.mode === "compact")) dwellTimer.restart()
        } else {
          dwellTimer.stop()
          leaveTimer.restart()
        }
      }
    }

    // ---------------------------------------------------------------- input region
    Item {
      id: hit
      x: Math.round((win.width - win.bw) / 2)
      y: 0
      width: Math.max(1, win.bw)
      // Hidden (fullscreen): a 3px strip along the top edge still reveals it.
      // The pill's inset above it counts as part of the island.
      height: win.mode === "hidden" ? 3 : Math.max(3, win.bh + win.s.islandTop)

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        // Swipes: a drag with the button held, or a two-finger touchpad
        // swipe (horizontal wheel), classified by Model.swipeAction.
        property point pressAt: Qt.point(0, 0)
        property bool swiped: false
        property real swipeX: 0
        function swipe(dx, dy) {
          var act = Model.swipeAction(dx, dy, win.mode)
          if (act !== "") win.s.tick()
          if (act === "tuck") win.s.tuckLive()
          else if (act === "dismiss") win.s.finishActivity()
          return act !== ""
        }
        onPressed: function(mouse) { pressAt = Qt.point(mouse.x, mouse.y); swiped = false; held = false; holdTimer.restart() }
        onReleased: holdTimer.stop()
        onPositionChanged: function(mouse) {
          if (pressed && !swiped && mouse.buttons & Qt.LeftButton)
            swiped = swipe(mouse.x - pressAt.x, mouse.y - pressAt.y)
        }
        Timer { id: swipeReset; interval: 300; onTriggered: parent.swipeX = 0 }
        // Apple: press and hold opens the island. The release then does nothing,
        // so a long press is not also a tap.
        property bool held: false
        Timer {
          id: holdTimer
          interval: 450
          onTriggered: {
            if (parent.swiped || parent.held) return
            if (win.mode !== "idle" && win.mode !== "compact") return
            parent.held = true
            win.s.tick()
            dwellTimer.stop()
            win.setExpanded(true)
          }
        }
        cursorShape: win.mode === "hidden" ? Qt.ArrowCursor : Qt.PointingHandCursor
        onClicked: function(mouse) {
          if (held) { held = false; return }
          if (swiped) return
          var m = win.mode
          if (win.t && Date.now() - win.modeSince < 450) return
          if (mouse.button === Qt.MiddleButton) { win.s.mediaToggle(); return }
          if (m === "controls" || m === "incoming" || m === "history" || m === "callview") return
          if (m === "compact" && win.s.live === "call") { win.openCall(); return }
          if (m === "alert" && win.t && win.t.source === "alarm-ring") {
            if (mouse.button === Qt.RightButton) win.s.snoozeAlarm()
            else win.s.stopAlarm()
            return
          }
          if (mouse.button === Qt.RightButton && m !== "notification") {
            if (win.t) win.s.finishActivity()
            win.openControls("main")
            return
          }
          if (m === "notification") {
            if (mouse.button === Qt.RightButton) win.s.notificationDismiss()
            else win.s.notificationActivate()
            return
          }
          if (m === "hud" || m === "alert") {
            win.s.finishActivity()
            if (mouse.button === Qt.LeftButton) win.setExpanded(true)
            return
          }
          win.s.tick()
          if (win.s.tapOpensApp && m === "compact" && win.s.live === "media" && mouse.button === Qt.LeftButton && win.s.openPlayerApp()) return
          dwellTimer.stop()
          win.setExpanded(!win.expanded)
        }
        onWheel: function(wheel) {
          // Two-finger sideways swipe: one gesture, then a short cooldown.
          // Off unless swipeToTuck: a touchpad's vertical scroll drifts
          // sideways enough to tuck activities away by accident.
          if (Math.abs(wheel.angleDelta.x) > Math.abs(wheel.angleDelta.y)) {
            if (!win.s.swipeToTuck) return
            // After a swipe, the rest of that gesture (and its inertia) is spent.
            if (swipeReset.running && swipeX === 0) { swipeReset.restart(); return }
            swipeX += wheel.angleDelta.x / 4
            if (swipe(swipeX, 0)) swipeX = 0
            swipeReset.restart()
            return
          }
          win.islandWheel(wheel)
        }
      }
    }

    // ---------------------------------------------------------------- second activity bubble
    // iOS "minimal" presentation: with two live activities the second one
    // detaches into a small round bubble beside the island.
    readonly property bool bubbleShown: win.s.secondLive !== "" && (win.mode === "idle" || win.mode === "compact")
    // Gooey split: the bubble starts behind the island, springs out, and a neck of
    // the same black stretches between them, thinning until it lets go. It
    // runs in reverse when the second activity ends.
    property real split: bubbleShown ? 1 : 0
    Behavior on split { SpringAnimation { spring: 3.6; damping: win.s.reduceMotion ? 1 : 0.35; epsilon: 0.002 } }
    readonly property real pillRight: Math.round((win.width + win.bw) / 2)
    Rectangle {
      readonly property real t: Math.max(0, Math.min(1, stage.split))
      visible: stage.split > 0.02 && t < 0.97
      color: win.s.islandColor
      x: stage.pillRight - 8
      width: Math.max(0, bubble.x + bubble.width / 2 - x)
      height: Math.max(0, bubble.height * 0.8 * (1 - t))
      y: win.s.islandTop + (bubble.height - height) / 2
      radius: height / 2
    }
    Item {
      id: bubble
      readonly property int size: win.s.notchHeight
      x: stage.pillRight - width / 2 + (width / 2 + 8) * stage.split
      y: win.s.islandTop
      width: win.s.bubbleWidth
      height: size
      scale: 0.6 + 0.4 * stage.split
      visible: stage.split > 0.02

      Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: win.s.islandColor
      }
      // Timer: a ring that drains; recording: pulsing dot; phone: glyph; music: art.
      Canvas {
        id: ring
        anchors.fill: parent
        anchors.margins: 3
        visible: win.s.secondLive === "timer"
        readonly property real frac: win.s.timerTotal > 0 ? win.s.timerLeft / win.s.timerTotal : 0
        onFracChanged: requestPaint()
        onPaint: {
          var c = getContext("2d")
          c.reset()
          c.lineWidth = 2.4
          c.strokeStyle = Qt.rgba(1, 0.62, 0.04, 0.25)
          c.beginPath(); c.arc(width / 2, height / 2, width / 2 - 1.5, 0, Math.PI * 2); c.stroke()
          c.strokeStyle = win.s.tint("orange")
          c.beginPath(); c.arc(width / 2, height / 2, width / 2 - 1.5, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * frac); c.stroke()
        }
      }
      Rectangle {
        visible: win.s.secondLive === "recording"
        anchors.centerIn: parent
        width: 8
        height: 8
        radius: 4
        color: win.s.tint("red")
      }
      Text {
        textFormat: Text.PlainText
        visible: win.s.secondLive === "ai"
        anchors.centerIn: parent
        text: win.s.glyphs.robot
        font.family: win.s.iconFont
        font.pixelSize: Model.TYPE.subhead
        color: win.s.tint("purple")
      }
      Text {
        textFormat: Text.PlainText
        visible: win.s.secondLive === "stopwatch"
        anchors.centerIn: parent
        width: parent.width - 8
        horizontalAlignment: Text.AlignHCenter
        text: Model.formatTime(win.s.stopwatchElapsed)
        font.family: win.s.textFont
        font.pixelSize: Model.TYPE.footnote
        font.weight: Font.DemiBold
        fontSizeMode: Text.Fit
        minimumPixelSize: 8
        color: win.s.tint("orange")
      }
      Text {
        textFormat: Text.PlainText
        visible: win.s.secondLive === "call"
        anchors.centerIn: parent
        text: ""
        font.family: win.s.iconFont
        font.pixelSize: Model.TYPE.subhead
        color: win.s.tint("green")
      }
      Text {
        textFormat: Text.PlainText
        visible: win.s.secondLive === "phone"
        anchors.centerIn: parent
        text: ""
        font.family: win.s.iconFont
        font.pixelSize: Model.TYPE.subhead
        color: win.s.tint("green")
      }
      Artwork {
        visible: win.s.secondLive === "media"
        anchors.centerIn: parent
        width: parent.width - 6
        height: width
        radius: width / 2
        source: win.s.artLocal
        fallbackGlyph: win.s.glyphs.music
        glyphFont: win.s.iconFont
        glyphColor: win.s.mediaAccent
      }
      Item {
        id: bubbleHit
        width: stage.bubbleShown ? parent.width : 0
        height: stage.bubbleShown ? parent.height : 0
        MouseArea {
          onWheel: function(wheel) { win.islandWheel(wheel) }
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (win.s.secondLive === "call") win.openCall()
            else if (win.s.secondLive === "phone") win.openControls("phone")
            else win.setExpanded(true)
          }
        }
      }
    }

    // ---------------------------------------------------------------- island
    Item {
      id: island
      x: Math.round((win.width - width) / 2)
      y: win.s.islandTop
      width: Math.max(0, win.bw)
      height: Math.max(0, win.bh)
      // The squish: a touch wider and shorter, anchored at the top edge.
      transform: Scale {
        origin.x: island.width / 2
        origin.y: 0
        xScale: 1 + 0.05 * win.squish
        yScale: 1 - 0.1 * win.squish
      }

      Item {
        id: shapeHolder
        layer.enabled: win.lift > 0.02
        layer.effect: MultiEffect {
          shadowEnabled: true
          shadowColor: Qt.rgba(0, 0, 0, 0.6 * win.lift)
          shadowBlur: 1.0
          blurMax: 36
          shadowVerticalOffset: 10 * win.lift
          autoPaddingEnabled: true
        }

        width: parent.width
        height: parent.height

        // iPhone bubble: fully round while it's small; opened up, its corners
        // are continuous-curvature (squircle) like iOS, not circular arcs.
        Shape {
          width: Math.max(0, win.bw)
          height: Math.max(0, win.bh)
          preferredRendererType: Shape.CurveRenderer
          ShapePath {
            id: bubblePath
            strokeWidth: -1
            fillColor: win.s.islandColor
            Behavior on fillColor { ColorAnimation { duration: 300 } }
            PathSvg { path: Model.squirclePath(win.bw, win.bh, win.brb, 0.6) }
          }
        }
      }

      // Content area: the body of the notch, clipped so views are revealed by
      // the growing shape rather than drawn ahead of it.
      Item {
        id: body
        width: Math.max(0, win.bw)
        height: Math.max(0, win.bh)
        clip: true

        // Everything inside moves together when a scroll brings another
        // activity to the front: it slides in from the scroll direction.
        Item {
          id: slider
          width: parent.width
          height: parent.height
          transform: Translate { y: win.slideY }

          // ------------------------------------------------ compact live activities
          Reveal {
            reduced: win.s.reduceMotion
            id: compactMedia
            shown: win.mode === "compact" && win.s.live === "media"
            width: win.geometryFor("compact").w
            height: win.s.notchHeight
            anchors.horizontalCenter: parent.horizontalCenter
            inDelay: 60

            Artwork {
              // Concentric: the same inset on every side of the round art.
              x: Math.round((win.s.notchHeight - width) / 2)
              anchors.verticalCenter: parent.verticalCenter
              width: win.artSize
              height: width
              radius: Math.round(width * 0.28)
              source: win.s.artLocal
              fallbackGlyph: win.s.glyphs.music
              glyphFont: win.s.iconFont
              glyphColor: win.s.mediaAccent
            }
            Waveform {
              anchors.right: parent.right
              anchors.rightMargin: win.edge + 2
              anchors.verticalCenter: parent.verticalCenter
              height: win.s.notchHeight - 12
              playing: win.s.isPlaying
              color: win.s.mediaAccent
              levels: win.s.spectrum
            }
          }

          CompactActivity {
            kind: "timer"
            tone: "orange"
            glyph: win.s.glyphs.timer
            trail: Model.formatTime(Math.ceil(win.s.timerLeft))
            trailOpacity: win.s.timerPausedLeft >= 0 ? 0.55 : 1
          }

          CompactActivity {
            kind: "ai"
            tone: "purple"
            glyph: win.s.glyphs.robot
            trail: win.s.aiLabel
            pulsing: true
          }

          CompactActivity {
            kind: "stopwatch"
            tone: "orange"
            glyph: win.s.glyphs.stopwatch
            trail: Model.formatTime(win.s.stopwatchElapsed)
            trailOpacity: win.s.stopwatchHeld >= 0 ? 0.55 : 1
          }

          CompactActivity {
            kind: "recording"
            tone: "red"
            trail: { win.s.now; return Model.formatTime((Date.now() - win.s.recordingSince) / 1000) }
            pulsing: win.s.recording
          }

          CompactActivity {
            kind: "call"
            tone: "green"
            glyph: ""
            trail: win.trailText
            pulsing: !!win.s.currentCall && win.s.currentCall.state !== "active"
            pulseMs: 600
          }

          // ------------------------------------------------ incoming call
          Reveal {
            reduced: win.s.reduceMotion
            id: incoming
            shown: win.mode === "incoming"
            width: win.geometryFor("incoming").w
            height: win.geometryFor("incoming").h
            anchors.horizontalCenter: parent.horizontalCenter
            property var call: win.s.ringingCall || ({})

            Rectangle {
              id: callerAvatar
              x: 14
              anchors.verticalCenter: parent.verticalCenter
              width: parent.height - 24
              height: width
              radius: width / 2
              color: Qt.rgba(1, 1, 1, 0.16)
              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: {
                  var n = String(incoming.call.name || "")
                  return n !== "" ? n.charAt(0).toUpperCase() : ""
                }
                font.family: text.length === 1 && /[A-Z0-9]/.test(text) ? win.s.textFont : win.s.iconFont
                font.pixelSize: 19
                font.weight: Font.DemiBold
                color: win.s.textColor
              }
            }
            Column {
              anchors.left: callerAvatar.right
              anchors.leftMargin: 12
              anchors.right: callButtons.left
              anchors.rightMargin: 10
              anchors.verticalCenter: parent.verticalCenter
              spacing: 1
              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: win.s.phoneName + (incoming.call.state === "waiting" ? " · Call Waiting" : "")
                font.family: win.s.textFont
                font.pixelSize: Model.TYPE.caption
                color: win.s.secondaryText
                elide: Text.ElideRight
              }
              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: win.s.callTitle(incoming.call)
                font.family: win.s.textFont
                font.pixelSize: Model.TYPE.callout
                font.weight: Font.DemiBold
                color: win.s.textColor
                elide: Text.ElideRight
              }
            }
            Row {
              id: callButtons
              anchors.right: parent.right
              anchors.rightMargin: 12
              anchors.verticalCenter: parent.verticalCenter
              spacing: 10
              Repeater {
                model: [
                  { glyph: "", color: "red", act: "hangup" },
                  { glyph: "", color: "green", act: "answer" }
                ]
                delegate: Rectangle {
                  required property var modelData
                  width: callerAvatar.width
                  height: width
                  radius: width / 2
                  color: win.s.tint(modelData.color)
                  scale: callTap.pressed ? 0.88 : callTap.containsMouse ? 1.06 : 1
                  Behavior on scale { SpringAnimation { spring: 6; damping: 0.35; epsilon: 0.005 } }
                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: modelData.glyph
                    font.family: win.s.iconFont
                    font.pixelSize: 19
                    color: "#ffffff"
                  }
                  MouseArea {
                    id: callTap
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      var path = win.s.ringingCall ? win.s.ringingCall.path : ""
                      if (modelData.act === "answer") { win.s.phone.answer(path); win.openCall() }
                      else win.s.phone.hangup(path)
                    }
                  }
                }
              }
            }
          }

          CompactActivity {
            kind: "phone"
            tone: "green"
            glyph: ""
            trail: win.trailText
          }

          // The clock lives in the island now: centered in the bare pill and
          // between the leading/trailing views of a live activity.
          Text {
            textFormat: Text.PlainText
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round((win.s.notchHeight - height) / 2)
            text: win.s.clockText
            font: clockMetrics.font
            color: win.s.textColor
            opacity: win.s.showClock && (win.mode === "idle" || win.mode === "compact") ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: win.mode === "idle" || win.mode === "compact" ? 260 : 90 } }
          }

          // ------------------------------------------------ alert (wide pill)
          Reveal {
            reduced: win.s.reduceMotion
            shown: win.mode === "alert"
            width: win.geometryFor("alert").w
            height: win.geometryFor("alert").h
            anchors.horizontalCenter: parent.horizontalCenter

            Row {
              x: 18
              anchors.verticalCenter: parent.verticalCenter
              spacing: 10
              Text {
                textFormat: Text.PlainText
                width: 20
                horizontalAlignment: Text.AlignHCenter
                anchors.verticalCenter: parent.verticalCenter
                text: win.lastAlert.icon || ""
                font.family: win.s.iconFont
                font.pixelSize: Model.TYPE.body
                color: win.s.tint(win.lastAlert.tint)
              }
              Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: win.lastAlert.title || ""
                font: alertTitleMetrics.font
                color: win.s.textColor
                elide: Text.ElideRight
                width: Math.min(implicitWidth, 300)
              }
            }
            Text {
              textFormat: Text.PlainText
              anchors.right: parent.right
              anchors.rightMargin: 20
              anchors.verticalCenter: parent.verticalCenter
              text: win.lastAlert.value || ""
              font: alertValueMetrics.font
              color: win.lastAlert.tint === "white" || win.lastAlert.tint === "secondary" ? win.s.secondaryText : win.s.tint(win.lastAlert.tint)
            }
          }

          // ------------------------------------------------ HUD (volume, brightness…)
          Reveal {
            reduced: win.s.reduceMotion
            shown: win.mode === "hud"
            width: win.geometryFor("hud").w
            height: win.geometryFor("hud").h
            anchors.horizontalCenter: parent.horizontalCenter

            Item {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: 14
              anchors.rightMargin: 16
              y: 0
              height: parent.height

              Text {
                textFormat: Text.PlainText
                id: hudIcon
                width: 22
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignHCenter
                text: win.lastHud.icon || ""
                font.family: win.s.iconFont
                font.pixelSize: 18
                color: win.s.tint(win.lastHud.tint)
              }
              Text {
                textFormat: Text.PlainText
                id: hudValue
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 38
                horizontalAlignment: Text.AlignRight
                text: win.lastHud.value || ""
                font: trailMetrics.font
                color: win.s.secondaryText
              }
              Rectangle {
                anchors.left: hudIcon.right
                anchors.leftMargin: 14
                anchors.right: hudValue.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                height: 6
                radius: 3
                color: win.s.trackColor
                Rectangle {
                  height: parent.height
                  radius: parent.radius
                  width: Math.max(parent.height, parent.width * Model.clamp((win.lastHud.percent || 0) / 100, 0, 1))
                  opacity: (win.lastHud.percent || 0) > 0 ? 1 : 0.0
                  color: win.s.paletteName === "theme" ? win.s.tint("accent") : win.s.textColor
                  Behavior on width { SpringAnimation { spring: 6; damping: 0.45; epsilon: 0.3 } }
                }
              }
            }
          }

          // ------------------------------------------------ notification peek
          Reveal {
            reduced: win.s.reduceMotion
            shown: win.mode === "notification"
            width: win.geometryFor("notification").w
            height: win.geometryFor("notification").h
            anchors.horizontalCenter: parent.horizontalCenter

            Artwork {
              id: notifImage
              x: 18
              y: Math.round((parent.height - height) / 2) + 4
              width: 44
              height: 44
              radius: 12
              source: win.lastNotif.image || ""
              fallbackGlyph: win.lastNotif.sms ? "" : win.s.glyphs.bell
              glyphFont: win.s.iconFont
              glyphColor: win.lastNotif.urgent ? win.s.tint("red") : win.s.textColor
              fallbackColor: Qt.rgba(1, 1, 1, 0.12)
            }
            // A dot's approval card: deny and approve, in the look of the incoming call's two buttons.
            Row {
              id: cardButtons
              visible: !!win.lastNotif.card
              anchors.right: parent.right
              anchors.rightMargin: 14
              anchors.verticalCenter: notifImage.verticalCenter
              spacing: 10
              Repeater {
                model: [
                  { glyph: win.s.glyphs.cross, color: "red", act: "deny", label: "Deny" },
                  { glyph: win.s.glyphs.check, color: "green", act: "approve", label: "Approve" }
                ]
                delegate: Rectangle {
                  required property var modelData
                  width: 36
                  height: width
                  radius: width / 2
                  color: win.s.tint(modelData.color)
                  scale: cardTap.pressed ? 0.88 : cardTap.containsMouse ? 1.06 : 1
                  Behavior on scale { SpringAnimation { spring: 6; damping: 0.35; epsilon: 0.005 } }
                  Accessible.role: Accessible.Button
                  Accessible.name: modelData.label
                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: modelData.glyph
                    font.family: win.s.iconFont
                    font.pixelSize: Model.TYPE.body
                    color: "#ffffff"
                  }
                  MouseArea {
                    id: cardTap
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: win.s.answerCard(modelData.act)
                  }
                }
              }
            }
            Column {
              anchors.left: notifImage.right
              anchors.leftMargin: 12
              anchors.right: cardButtons.visible ? cardButtons.left : parent.right
              anchors.rightMargin: cardButtons.visible ? 12 : 20
              anchors.verticalCenter: notifImage.verticalCenter
              spacing: 1

              Item {
                width: parent.width
                height: appLabel.implicitHeight
                Text {
                  textFormat: Text.PlainText
                  id: appLabel
                  anchors.left: parent.left
                  anchors.right: nowLabel.left
                  anchors.rightMargin: 8
                  text: win.lastNotif.app || ""
                  font.family: win.s.textFont
                  font.pixelSize: Model.TYPE.caption
                  font.weight: Font.Medium
                  color: win.s.secondaryText
                  elide: Text.ElideRight
                }
                Text {
                  textFormat: Text.PlainText
                  id: nowLabel
                  anchors.right: parent.right
                  text: "now"
                  font.family: win.s.textFont
                  font.pixelSize: Model.TYPE.caption
                  color: win.s.secondaryText
                }
              }
              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: win.lastNotif.title || ""
                font.family: win.s.textFont
                font.pixelSize: Model.TYPE.subhead
                font.weight: Font.DemiBold
                color: win.lastNotif.urgent ? win.s.tint("red") : win.s.textColor
                elide: Text.ElideRight
                maximumLineCount: 1
              }
              Text {
                textFormat: Text.PlainText
                width: parent.width
                visible: text !== ""
                text: win.lastNotif.body || ""
                font.family: win.s.textFont
                font.pixelSize: Model.TYPE.footnote
                color: win.s.secondaryText
                elide: Text.ElideRight
                maximumLineCount: 1
              }
            }
          }

          // ------------------------------------------------ expanded
          Reveal {
            reduced: win.s.reduceMotion
            shown: win.mode === "expanded" && win.mediaPage
            width: win.geometryFor("expanded").w
            height: win.geometryFor("expanded").h
            anchors.horizontalCenter: parent.horizontalCenter
            inDelay: 130
            inDuration: 380

            ExpandedView {
              anchors.fill: parent
              s: win.s
              active: win.mode === "expanded" && win.mediaPage
              keyboard: win.keyHeld && !win.controlsOpen
              onOutputClicked: win.openControls("audio")
              onCloseRequested: win.setExpanded(false)
            }
          }

          // Any other running activity at full size.
          Reveal {
            reduced: win.s.reduceMotion
            shown: win.mode === "expanded" && !win.mediaPage
            width: win.geometryFor("expanded").w
            height: win.geometryFor("expanded").h
            anchors.horizontalCenter: parent.horizontalCenter
            inDelay: 130
            inDuration: 380

            ActivityCard {
              anchors.fill: parent
              s: win.s
              kind: win.page && !win.mediaPage ? win.page.kind : ""
            }
          }

          // ------------------------------------------------ call
          Reveal {
            reduced: win.s.reduceMotion
            shown: win.mode === "callview"
            width: callView.preferredWidth
            height: Math.max(0, win.bh)
            anchors.horizontalCenter: parent.horizontalCenter
            inDelay: 110
            inDuration: 320

            CallView {
              id: callView
              anchors.fill: parent
              s: win.s
              active: win.callOpen
              focus: win.callOpen
              onCloseRequested: win.callOpen = false
            }
          }

          // ------------------------------------------------ history
          Reveal {
            reduced: win.s.reduceMotion
            shown: win.mode === "history"
            width: historyView.preferredWidth
            height: Math.max(0, win.bh)
            anchors.horizontalCenter: parent.horizontalCenter
            inDelay: 110
            inDuration: 340

            HistoryView {
              id: historyView
              anchors.fill: parent
              s: win.s
              active: win.mode === "history"
              onCloseRequested: win.scrollStep(-1)
            }
          }

          // ------------------------------------------------ control center
          Reveal {
            reduced: win.s.reduceMotion
            shown: win.mode === "controls"
            width: win.cc ? win.cc.preferredWidth : 0
            height: Math.max(0, win.bh)
            anchors.horizontalCenter: parent.horizontalCenter
            inDelay: 110
            inDuration: 320

            Loader {
              id: ccLoader
              anchors.fill: parent
              active: win.s.controlCenter
              sourceComponent: ControlCenter {
                s: win.s
                islandWin: win
                active: win.controlsOpen
              }
            }
          }
        }
      }
    }

    // Privacy indicators: orange while an app captures the microphone, green
    // while one holds the camera. They sit beside the island rather than in
    // it — the pill's shadow layer clips its own children, and a live
    // activity already fills the pill edge to edge.
    Row {
      spacing: 4
      x: island.x + island.width + 6
      y: win.s.islandTop + Math.round((win.bh - 6) / 2)
      visible: win.mode === "idle" || win.mode === "compact"

      Rectangle {
        width: 6
        height: 6
        radius: 3
        color: win.s.tint("orange")
        opacity: win.s.micInUse ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 250 } }
      }
      Rectangle {
        width: 6
        height: 6
        radius: 3
        color: win.s.tint("green")
        opacity: win.s.cameraInUse ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 250 } }
      }
    }
  }
}
