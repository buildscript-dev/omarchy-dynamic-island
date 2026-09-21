import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import "IslandModel.js" as Model

// The island's Control Center: everything the right side of the bar does
// (Wi-Fi, Bluetooth, sound, earbuds, phone, tray, power), drawn inside the
// island the way iOS draws it — tiles and fat sliders on the first page,
// a detail page per tile that the island springs open to fit.
//
// It talks to the same backends as the stock Omarchy panels (Quickshell
// Networking / Bluetooth / Pipewire and the omarchy-* helpers), so every
// action behaves exactly like the native panel's.
Item {
  id: root

  property var s: null
  property var win: null
  property bool active: false
  property string page: "main"   // main | wifi | bluetooth | audio | buds | phone | call | messages | thread | notifications | calendar | power

  readonly property int pad: 18
  readonly property int innerWidth: width - pad * 2
  // The island sizes itself to this, so each page gets exactly its height.
  // Reading a conversation needs room, so those pages get a bigger panel.
  readonly property bool roomy: page === "thread"
  readonly property int preferredWidth: Math.min(roomy ? 620 : 440, Math.max(360, (win ? win.width : 640) - 48))
  readonly property int preferredHeight: Math.min(roomy ? 760 : 560, Math.ceil(pageHeight) + pad * 2)
  readonly property real pageHeight: page === "main" ? mainPage.implicitHeight
    : page === "wifi" ? wifiPage.implicitHeight
    : page === "bluetooth" ? btPage.implicitHeight
    : page === "audio" ? audioPage.implicitHeight
    : page === "buds" ? budsPage.implicitHeight
    : page === "phone" ? phonePage.implicitHeight
    : page === "call" ? callPage.implicitHeight
    : page === "messages" ? messagesPage.implicitHeight
    : page === "thread" ? threadPage.implicitHeight
    : page === "notifications" ? notifPage.implicitHeight
    : page === "calendar" ? calPage.implicitHeight
    : powerPage.implicitHeight

  // A password field is the only thing that needs the keyboard.
  readonly property bool wantsKeyboard: active && page === "wifi" && passwordSsid !== ""

  onActiveChanged: {
    if (!active) { page = "main"; cancelPassword(); return }
    Qt.callLater(function() { root.forceActiveFocus() })
    s.checkUpdates()
    if (s.phone) s.phone.refresh()
  }
  // Esc steps back a page, then closes — the keyboard way out.
  focus: true
  Keys.onEscapePressed: { if (page !== "main") back(); else win.closeControls() }
  onPageChanged: {
    cancelPassword(); armedAction = ""
    keypadInCall = false
    // Typing goes straight to the dialer / message box.
    if (page === "call") Qt.callLater(function() { dialLabel.forceActiveFocus() })
    else if (page === "thread") {
      // Opened straight from a shortcut: show the newest conversation.
      if (!root.threadInfo.name && root.allChats.length > 0) { root.openThread(root.allChats[0]); return }
      Qt.callLater(function() { (root.threadInfo.isNew === true ? toField : draftField).forceActiveFocus() })
    }
  }

  function go(p) { page = p }
  function back() { page = "main" }

  // ================================================================ colors
  readonly property color fg: s.textColor
  readonly property color dim: s.secondaryText
  readonly property color tileOff: Qt.rgba(fg.r, fg.g, fg.b, 0.1)
  readonly property color tileHover: Qt.rgba(fg.r, fg.g, fg.b, 0.15)
  function onColor(name) { return s.tint(name) }

  // ================================================================ Wi-Fi
  readonly property var netDevices: Networking.devices ? Networking.devices.values : []
  function findDevice(type) {
    var fallback = null
    for (var i = 0; i < netDevices.length; i++) {
      var d = netDevices[i]
      if (!d || d.type !== type) continue
      if (d.connected) return d
      if (!fallback) fallback = d
    }
    return fallback
  }
  readonly property var wifiDevice: findDevice(DeviceType.Wifi)
  readonly property var wiredDevice: findDevice(DeviceType.Wired)
  readonly property bool wifiOn: !!Networking.wifiEnabled
  readonly property var wifiObjects: wifiDevice && wifiDevice.networks ? wifiDevice.networks.values : []
  // Rows are primitive snapshots; live WifiNetwork objects are resolved by
  // SSID only when acting (NetworkManager can destroy them mid-scan).
  readonly property var wifiRows: {
    var rows = []
    var seen = {}
    for (var i = 0; i < wifiObjects.length; i++) {
      var n = wifiObjects[i]
      if (!n || !n.name || seen[n.name]) continue
      seen[n.name] = true
      rows.push({ ssid: n.name, connected: !!n.connected, known: !!n.known,
        signal: Math.round((n.signalStrength || 0) * 100),
        secure: n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe,
        changing: !!n.stateChanging })
    }
    rows.sort(function(a, b) {
      if (a.connected !== b.connected) return a.connected ? -1 : 1
      if (a.known !== b.known) return a.known ? -1 : 1
      return b.signal - a.signal
    })
    return rows
  }
  readonly property var wifiCurrent: {
    for (var i = 0; i < wifiRows.length; i++) if (wifiRows[i].connected) return wifiRows[i]
    return null
  }
  readonly property bool wired: !!(wiredDevice && wiredDevice.connected)
  function wifiGlyph(signal) {
    var icons = ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"]
    return icons[Math.max(0, Math.min(4, Math.ceil(signal / 20) - 1))]
  }
  function networkFor(ssid) {
    for (var i = 0; i < wifiObjects.length; i++) if (wifiObjects[i] && wifiObjects[i].name === ssid) return wifiObjects[i]
    return null
  }

  property string wifiBusySsid: ""
  property string wifiFailSsid: ""
  property string wifiFailText: ""
  property string passwordSsid: ""
  property var wifiActing: null

  function cancelPassword() { passwordSsid = "" }
  function wifiRowClicked(row) {
    if (wifiBusySsid !== "") return
    if (row.connected) { wifiAct(row.ssid, function(n) { n.disconnect() }); return }
    if (row.known || !row.secure) { wifiAct(row.ssid, function(n) { n.connect() }); return }
    passwordSsid = passwordSsid === row.ssid ? "" : row.ssid
  }
  function wifiConnectWithPassword(ssid, pass) {
    if (pass === "") return
    wifiAct(ssid, function(n) { n.connectWithPsk(pass) })
  }
  function wifiForget(ssid) { wifiAct(ssid, function(n) { n.forget() }) }
  function wifiAct(ssid, fn) {
    var n = networkFor(ssid)
    if (!n) return
    wifiFailSsid = ""
    wifiBusySsid = ssid
    wifiActing = n
    fn(n)
    wifiTimeout.restart()
  }
  function wifiSettle() {
    if (wifiBusySsid === "") return
    for (var i = 0; i < wifiRows.length; i++) {
      var r = wifiRows[i]
      if (r.ssid === wifiBusySsid && !r.changing) {
        wifiBusySsid = ""
        wifiActing = null
        wifiTimeout.stop()
        if (r.connected) passwordSsid = ""
      }
    }
  }
  onWifiRowsChanged: settleLater.restart()
  Timer { id: settleLater; interval: 400; onTriggered: root.wifiSettle() }
  Timer {
    id: wifiTimeout
    interval: 25000
    onTriggered: { root.wifiFailSsid = root.wifiBusySsid; root.wifiFailText = "Couldn't connect"; root.wifiBusySsid = ""; root.wifiActing = null }
  }
  Connections {
    target: root.wifiActing
    ignoreUnknownSignals: true
    function onConnectionFailed(reason) {
      var ssid = root.wifiBusySsid
      root.wifiBusySsid = ""
      root.wifiActing = null
      wifiTimeout.stop()
      root.wifiFailSsid = ssid
      var wrongPass = reason === ConnectionFailReason.NoSecrets || reason === ConnectionFailReason.WifiAuthTimeout
      root.wifiFailText = wrongPass ? "Wrong password" : "Couldn't connect"
      if (wrongPass) root.passwordSsid = ssid
    }
  }
  // Scan only while the Wi-Fi page is up, like the stock panel.
  property var scanner: null
  readonly property bool wantScan: active && page === "wifi" && wifiOn
  function syncScanner() {
    var next = wantScan ? wifiDevice : null
    if (scanner && scanner !== next) scanner.scannerEnabled = false
    scanner = next
    if (scanner) scanner.scannerEnabled = true
  }
  onWantScanChanged: syncScanner()
  onWifiDeviceChanged: syncScanner()
  Component.onDestruction: {
    if (scanner) scanner.scannerEnabled = false
    if (btAdapter && btAdapter.discovering && discoveryMine) btAdapter.discovering = false
  }
  function toggleWifi() { Networking.wifiEnabled = !Networking.wifiEnabled }

  // ================================================================ Bluetooth
  readonly property var btAdapter: Bluetooth.defaultAdapter
  readonly property bool btOn: !!(btAdapter && btAdapter.enabled)
  readonly property var btDevices: Bluetooth.devices ? Bluetooth.devices.values : []
  function btName(d) { return String(d.name || d.deviceName || d.address || "Device") }
  function btKnown(d) { return !!(d.paired || d.bonded || d.trusted) }
  readonly property var btConnected: {
    var out = []
    for (var i = 0; i < btDevices.length; i++) if (btDevices[i] && btDevices[i].connected) out.push(btDevices[i])
    return out
  }
  readonly property var btRows: {
    var known = [], found = []
    for (var i = 0; i < btDevices.length; i++) {
      var d = btDevices[i]
      if (!d || !d.address) continue
      var named = !!(d.name || d.deviceName) && String(d.name || d.deviceName).replace(/[-:]/g, "") !== String(d.address).replace(/:/g, "")
      var row = { address: String(d.address), name: btName(d), connected: !!d.connected, known: btKnown(d),
        icon: String(d.icon || ""), battery: d.batteryAvailable ? Math.round(d.battery <= 1 ? d.battery * 100 : d.battery) : -1 }
      if (row.known || row.connected) known.push(row)
      else if (named) found.push(row)
    }
    known.sort(function(a, b) { return a.connected === b.connected ? a.name.localeCompare(b.name) : (a.connected ? -1 : 1) })
    return { known: known, found: found }
  }
  property var btPending: ({})
  function btSetPending(addr, what) {
    var p = Object.assign({}, btPending)
    if (what) p[addr] = what; else delete p[addr]
    btPending = p
    btPendingTimer.restart()
  }
  onBtRowsChanged: {
    var p = Object.assign({}, btPending), changed = false
    var all = btRows.known.concat(btRows.found)
    for (var addr in p) {
      for (var i = 0; i < all.length; i++) {
        if (all[i].address !== addr) continue
        if ((p[addr] === "connecting" && all[i].connected) || (p[addr] === "disconnecting" && !all[i].connected)
            || (p[addr] === "forgetting" && !all[i].known)) { delete p[addr]; changed = true }
      }
    }
    if (changed) btPending = p
  }
  Timer { id: btPendingTimer; interval: 20000; onTriggered: root.btPending = ({}) }
  function btClick(row) {
    if (btPending[row.address]) return
    if (row.connected) {
      btSetPending(row.address, "disconnecting")
      Quickshell.execDetached(["omarchy-bluetooth-device", "disconnect", row.address])
    } else {
      btSetPending(row.address, "connecting")
      Quickshell.execDetached(["omarchy-bluetooth-device", row.known ? "connect" : "pair", row.address])
    }
  }
  function btForget(row) {
    btSetPending(row.address, "forgetting")
    Quickshell.execDetached(["omarchy-bluetooth-device", "forget", row.address])
  }
  function toggleBluetooth() {
    if (!btAdapter) return
    Quickshell.execDetached(["omarchy-bluetooth-power", btAdapter.enabled ? "off" : "on"])
  }
  function btGlyph(icon) {
    if (icon.indexOf("headset") !== -1 || icon.indexOf("headphone") !== -1 || icon.indexOf("audio") !== -1) return "󰋋"
    if (icon.indexOf("phone") !== -1) return "󰏲"
    if (icon.indexOf("keyboard") !== -1) return "󰌌"
    if (icon.indexOf("mouse") !== -1) return "󰍽"
    if (icon.indexOf("computer") !== -1) return "󰟀"
    return "󰂯"
  }
  // Discover new devices while the Bluetooth page is open.
  property bool discoveryMine: false
  readonly property bool wantDiscovery: active && page === "bluetooth" && btOn
  onWantDiscoveryChanged: {
    if (!btAdapter) return
    if (wantDiscovery && !btAdapter.discovering) { btAdapter.discovering = true; discoveryMine = true }
    else if (!wantDiscovery && discoveryMine) { btAdapter.discovering = false; discoveryMine = false }
  }

  // ================================================================ sound
  readonly property var sink: Pipewire.defaultAudioSink
  readonly property var source: Pipewire.defaultAudioSource
  readonly property var pwNodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var sinks: {
    var out = []
    for (var i = 0; i < pwNodes.length; i++) { var n = pwNodes[i]; if (n && n.isSink && !n.isStream && n.audio) out.push(n) }
    return out
  }
  readonly property var sources: {
    var out = []
    for (var i = 0; i < pwNodes.length; i++) {
      var n = pwNodes[i]
      if (n && !n.isSink && !n.isStream && n.audio && String(n.name || "").indexOf(".monitor") === -1) out.push(n)
    }
    return out
  }
  PwObjectTracker { objects: [root.sink, root.source].concat(root.sinks).concat(root.sources) }
  function nodeName(n) { return n ? String(n.description || n.nickname || n.name || "Device") : "" }
  readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
  readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
  readonly property bool micMuted: source && source.audio ? source.audio.muted : false
  function setVolume(v) { if (sink && sink.audio) { sink.audio.volume = Model.clamp(v, 0, 1); if (v > 0 && sink.audio.muted) sink.audio.muted = false } }
  function toggleMute() { if (sink && sink.audio) sink.audio.muted = !sink.audio.muted }
  function toggleMic() { if (source && source.audio) source.audio.muted = !source.audio.muted }
  function setSink(n) {
    Pipewire.preferredDefaultAudioSink = n
    if (n && n.id !== undefined && n.name) Quickshell.execDetached(["omarchy-audio-output-set-default", String(n.id), String(n.name)])
  }
  function setSource(n) {
    Pipewire.preferredDefaultAudioSource = n
    if (n && n.id !== undefined && n.name) Quickshell.execDetached(["omarchy-audio-input-set-default", String(n.id), String(n.name)])
  }

  // ================================================================ brightness
  property real brightness: -1
  readonly property string monitorName: win && win.screenName ? win.screenName : ""
  Process {
    id: brightRead
    // Always the island's own screen, not wherever the pointer happens to be.
    command: ["omarchy-brightness-display", "--no-osd", "--monitor", root.monitorName]
    stdout: StdioCollector {
      onStreamFinished: {
        var v = parseInt(String(text || "").trim(), 10)
        if (isNaN(v) || v <= 0) { if (!brightDebounce.running && !brightSet.running) root.brightness = -1; return }
        if (!brightSet.running && !brightDebounce.running) root.brightness = Model.clamp(v / 100, 0, 1)
      }
    }
  }
  property real brightTarget: 0
  function setBrightness(v) { brightness = Model.clamp(v, 0.01, 1); brightTarget = brightness; brightDebounce.restart() }
  Timer {
    id: brightDebounce
    interval: 90
    onTriggered: {
      if (brightSet.running) { restart(); return }
      brightSet.command = ["omarchy-brightness-display", "--no-osd", "--monitor", root.monitorName, Math.round(root.brightTarget * 100) + "%"]
      brightSet.running = true
    }
  }
  Process { id: brightSet }

  // ================================================================ toggles
  property bool nightLight: false
  property bool stayAwake: false
  property string powerProfile: ""
  property var powerProfiles: []
  Process {
    id: nightRead
    command: ["omarchy-toggle-nightlight", "--status"]
    stdout: StdioCollector { onStreamFinished: { try { root.nightLight = !!JSON.parse(text).enabled } catch (e) {} } }
  }
  Process {
    id: awakeRead
    command: ["omarchy-toggle-idle", "status"]
    stdout: StdioCollector { onStreamFinished: { try { root.stayAwake = !!JSON.parse(text).enabled } catch (e) {} } }
  }
  Process {
    id: profileRead
    command: ["omarchy-powerprofiles-list", "--active-state"]
    stdout: StdioCollector {
      onStreamFinished: {
        var list = [], cur = ""
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var p = lines[i].split("\t")
          if (!p[0]) continue
          list.push(p[0])
          if (p[1] === "1") cur = p[0]
        }
        root.powerProfiles = list
        root.powerProfile = cur
      }
    }
  }
  function refreshToggles() {
    nightRead.running = true
    awakeRead.running = true
    profileRead.running = true
    brightRead.running = true
  }
  onVisibleChanged: if (visible) refreshToggles()
  Timer { interval: 3000; repeat: true; running: root.active; onTriggered: root.refreshToggles() }
  function run(cmd, after) {
    Quickshell.execDetached(cmd)
    if (after) refreshSoon.restart()
  }
  Timer { id: refreshSoon; interval: 700; onTriggered: root.refreshToggles() }
  function toggleNight() { nightLight = !nightLight; run(["omarchy-toggle-nightlight"], true) }
  function toggleAwake() { stayAwake = !stayAwake; run(["omarchy-toggle-idle"], true) }
  function cycleProfile() {
    if (powerProfiles.length === 0) return
    var next = powerProfiles[(powerProfiles.indexOf(powerProfile) + 1) % powerProfiles.length]
    powerProfile = next
    run(["omarchy-powerprofiles-set", s.onBattery ? "battery" : "ac", next], true)
  }
  function profileGlyph(p) { return p === "performance" ? "󰓅" : p === "power-saver" ? "󰾆" : "󰾅" }
  function profileLabel(p) { return p === "performance" ? "Performance" : p === "power-saver" ? "Power Saver" : "Balanced" }
  function toggleDnd() { run(["omarchy-shell", "-q", "notifications", "toggleDnd"], false) }

  // Phone mirroring (Taildroid) — driven through its own service.
  readonly property var phone: s.phone
  readonly property bool hasPhone: !!phone
  readonly property bool phoneRunning: !!(phone && phone.controlling)
  readonly property var phoneDevice: phone ? phone.selectedDevice : null
  function phoneName(d) { return d ? (d.name && d.name !== d.serial ? String(d.name) : String(d.serial || "Android")) : "Android" }
  function phoneSub(d) {
    var bits = []
    if (d.state && d.state !== "device") bits.push(d.state)
    else bits.push(d.transport === "tcp" ? "Tailscale / Wi-Fi" : "USB")
    if (d.battery !== undefined && d.battery !== null) bits.push(d.battery + "%")
    return bits.join(" · ")
  }
  function togglePhone() { if (phone) phone.toggleControl() }
  property string pairAddress: ""
  property string pairCode: ""

  // Continuity (phoned): calls, messages, battery, links.
  readonly property var ps: phone && phone.pstate ? phone.pstate : ({})
  readonly property var psPhone: ps.phone || ({})
  readonly property var psBattery: ps.battery || ({ level: -1 })
  readonly property var psBt: ps.bluetooth || ({})
  readonly property var psKde: ps.kdeconnect || ({})
  readonly property bool callsReady: !!(ps.hfp && ps.hfp.ready)
  readonly property var call: s.currentCall || s.ringingCall
  property string dialNumber: ""
  property bool keypadInCall: false
  property var threadInfo: ({ threadId: 0, name: "", addresses: [] })
  property string draft: ""
  property string newRecipient: ""
  Connections {
    target: root.s
    // Clicking the peek asked for a reply; open that card's box.
    // Clicking the peek asked for the whole notification; open it here.
    function onPendingNotifChanged() {
      if (!root.s.pendingNotif || !root.win.isTarget()) return
      root.activateNotif(root.s.pendingNotif)
      Qt.callLater(function() { root.s.pendingNotif = null })
    }
    function onPendingThreadChanged() {
      // Every monitor has an island; only the one showing it opens the thread.
      if (!root.s.pendingThread || !root.win.isTarget()) return
      root.openThread(root.s.pendingThread)
      Qt.callLater(function() { root.s.pendingThread = null })
    }
  }
  function keypadPress(k) {
    if (root.call && root.call.state === "active") root.phone.tones(k)
    else dialNumber += k
  }
  Process {
    id: pasteNumber
    command: ["wl-paste", "--no-newline"]
    stdout: StdioCollector { onStreamFinished: root.dialNumber += String(text || "").replace(/[^0-9*#+]/g, "") }
  }
  // A phone notification is just the newest line of a chat, so open the chat.
  function activateNotif(n) {
    if (n.phone) {
      var c = root.chatFor(n.app, n.title)
      if (c) { root.openThread({ kind: "chat", key: c.key, app: c.app, replyId: c.replyId,
                                 name: c.title, face: c.icon, body: "", date: c.date }); return }
    }
    if (!root.s.openForApp(n.app)) Quickshell.execDetached(["omarchy-shell", "-q", "notifications", "invokeLast"])
  }
  // Every conversation the phone knows about, newest first: real SMS threads,
  // and the chats that only reach this machine as notifications.
  readonly property var allChats: {
    var out = []
    var sms = root.phone ? root.phone.conversations : []
    for (var i = 0; i < sms.length; i++) {
      var t = sms[i]
      out.push({ kind: "sms", threadId: t.threadId, key: "", app: "Messages", replyId: "",
                 name: t.name || (t.addresses || []).join(", "), face: t.face || "",
                 body: String(t.body || ((t.attachments || []).length ? "Attachment" : "")),
                 outgoing: !!t.outgoing, date: t.date, unread: !t.read && !t.outgoing, addresses: t.addresses || [] })
    }
    var ch = root.phone ? root.phone.chats : []
    for (var j = 0; j < ch.length; j++) {
      var c = ch[j]
      out.push({ kind: "chat", threadId: 0, key: c.key, app: c.app, replyId: String(c.replyId || ""),
                 name: c.title, face: c.icon || "", body: String(c.body || ""),
                 outgoing: !!c.outgoing, date: c.date, unread: false, addresses: [] })
    }
    out.sort(function(a, b) { return b.date - a.date })
    return out
  }
  function chatFor(app, title) {
    var ch = root.phone ? root.phone.chats : []
    for (var i = 0; i < ch.length; i++) {
      if (String(ch[i].app) === String(app) && String(ch[i].title) === String(title)) return ch[i]
    }
    return null
  }
  // One conversation view serves both kinds; only where the text comes from differs.
  readonly property var threadMsgs: {
    if (root.threadInfo.kind === "chat") {
      var raw = root.phone ? root.phone.chatMessages : []
      var out = []
      for (var i = 0; i < raw.length; i++)
        out.push({ body: raw[i].text, outgoing: !!raw[i].out, date: raw[i].date, attachments: [], files: [] })
      return out
    }
    var t = root.phone && root.phone.threadMessages.length > 0 ? root.phone.threadMessages : (root.threadInfo.seed || [])
    return t
  }
  function openThread(t) {
    if (!t) {
      threadInfo = { kind: "sms", isNew: true, threadId: 0, key: "", app: "Messages", replyId: "",
                     name: "New Message", addresses: [], face: "", seed: [] }
    } else {
      threadInfo = { kind: String(t.kind || "sms"), isNew: false, threadId: t.threadId || 0, key: String(t.key || ""),
                     app: String(t.app || "Messages"), replyId: String(t.replyId || ""),
                     name: t.name, addresses: t.addresses || [], face: t.face || "",
                     seed: t.body ? [{ body: t.body, outgoing: !!t.outgoing, date: t.date, attachments: [], files: [] }] : [] }
      if (threadInfo.kind === "chat") root.phone.openChat(threadInfo.key)
      else root.phone.openThread(threadInfo.threadId)
    }
    draft = ""
    newRecipient = ""
    go("thread")
  }
  function sendDraft() {
    if (draft.trim() === "") return
    if (threadInfo.kind === "chat") {
      if (threadInfo.replyId === "") return
      phone.replyTo(threadInfo.replyId, draft, threadInfo.key)
    }
    else if (threadInfo.threadId) phone.sendSms(threadInfo.threadId, draft, [])
    else if (newRecipient.trim() !== "") phone.sendSms(0, draft, [newRecipient.trim()])
    draft = ""
  }
  function phoneLinkText() {
    var bits = []
    var p = psPhone
    if (p.serial) bits.push(p.transport === "usb" ? "USB" : "Wi-Fi")
    if (psBattery.level >= 0) bits.push(psBattery.level + "%" + (psBattery.charging ? " ⚡" : ""))
    if (ps.signal && ps.signal.network) bits.push(ps.signal.network)
    return bits.length ? bits.join(" · ") : "Not connected"
  }

  // Earbuds (OnePlus Experience) — the shared service loads their state.
  readonly property var buds: s.buds
  readonly property bool hasBuds: !!buds && buds.daemonReachable
  readonly property var budsStatus: buds ? buds.status : null
  function budsLevel(part) { return part && part.level >= 0 ? part.level + "%" : "–" }
  readonly property var modeNames: ({ anc: "Noise Cancel", smart: "Smart ANC", transparency: "Transparency", off: "Off" })
  readonly property var modeGlyphs: ({ anc: "󰟎", smart: "󰧑", transparency: "󰈈", off: "󰋋" })

  // ================================================================ tray
  readonly property var trayItems: SystemTray.items ? SystemTray.items.values : []

  // ================================================================ building blocks
  component Label: Text {
    font.family: root.s.textFont
    font.pixelSize: 13
    color: root.fg
    elide: Text.ElideRight
    textFormat: Text.PlainText
  }
  component Glyph: Text {
    font.family: root.s.iconFont
    font.pixelSize: 16
    color: root.fg
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
  }

  // Wide iOS tile: round icon (tap = toggle) + title/subtitle (tap = open page).
  component Tile: Rectangle {
    id: tile
    property string glyph: ""
    property string title: ""
    property string subtitle: ""
    property bool on: false
    property color accent: root.onColor("blue")
    property bool chevron: true
    signal toggled()
    signal opened()
    width: (root.innerWidth - 10) / 2
    height: 58
    radius: 20
    color: tileMouse.containsMouse ? root.tileHover : root.tileOff
    Behavior on color { ColorAnimation { duration: 120 } }
    scale: tileMouse.pressed ? 0.97 : 1
    Behavior on scale { SpringAnimation { spring: 6; damping: 0.4; epsilon: 0.005 } }

    MouseArea {
      id: tileMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: tile.opened()
    }
    Rectangle {
      id: tileIcon
      x: 10
      anchors.verticalCenter: parent.verticalCenter
      width: 38
      height: 38
      radius: 19
      color: tile.on ? tile.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.14)
      Behavior on color { ColorAnimation { duration: 160 } }
      scale: iconMouse.pressed ? 0.88 : 1
      Behavior on scale { SpringAnimation { spring: 6; damping: 0.35; epsilon: 0.005 } }
      Glyph { anchors.centerIn: parent; text: tile.glyph; font.pixelSize: 18; color: tile.on ? "#ffffff" : root.fg }
      MouseArea { id: iconMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tile.toggled() }
    }
    Column {
      anchors.left: tileIcon.right
      anchors.leftMargin: 10
      anchors.right: tile.chevron ? chev.left : parent.right
      anchors.rightMargin: 6
      anchors.verticalCenter: parent.verticalCenter
      spacing: 1
      Label { width: parent.width; text: tile.title; font.weight: Font.DemiBold }
      Label { width: parent.width; text: tile.subtitle; visible: text !== ""; font.pixelSize: 11; color: root.dim }
    }
    Glyph { id: chev; visible: tile.chevron; anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: "󰅂"; font.pixelSize: 14; color: root.dim }
  }

  // Fat iOS slider with its icon inside the track.
  component FatSlider: Item {
    id: sl
    property real value: 0
    property string glyph: ""
    property bool dimmed: false
    signal moved(real v)
    signal glyphClicked()
    height: 36
    Rectangle {
      id: track
      anchors.fill: parent
      radius: height / 2
      color: root.tileOff
      clip: true
      Rectangle {
        width: Math.max(track.height, track.width * Model.clamp(sl.value, 0, 1))
        height: parent.height
        radius: track.radius
        color: sl.dimmed ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.35) : root.fg
        Behavior on width { enabled: !drag.pressed; SpringAnimation { spring: 5; damping: 0.45; epsilon: 0.3 } }
      }
    }
    MouseArea {
      id: drag
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      function apply(mx) { sl.moved(Model.clamp(mx / width, 0, 1)) }
      onPressed: function(m) { if (m.x < 40) return; apply(m.x) }
      onPositionChanged: function(m) { if (pressed && m.x >= 0) apply(m.x) }
      onClicked: function(m) { if (m.x < 40) sl.glyphClicked() }
      onWheel: function(w) { sl.moved(Model.clamp(sl.value + (w.angleDelta.y > 0 ? 0.05 : -0.05), 0, 1)) }
    }
    Glyph {
      x: 12
      anchors.verticalCenter: parent.verticalCenter
      text: sl.glyph
      font.pixelSize: 17
      color: sl.dimmed ? root.fg : "#000000"
    }
  }

  // Small round button for the quick-action row.
  component Round: Item {
    id: rb
    property string glyph: ""
    property bool on: false
    property color accent: root.onColor("blue")
    property string hint: ""
    signal clicked()
    width: 42
    height: 42
    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: rb.on ? rb.accent : rbMouse.containsMouse ? root.tileHover : root.tileOff
      Behavior on color { ColorAnimation { duration: 140 } }
      scale: rbMouse.pressed ? 0.88 : 1
      Behavior on scale { SpringAnimation { spring: 6; damping: 0.35; epsilon: 0.005 } }
    }
    Glyph { anchors.centerIn: parent; text: rb.glyph; font.pixelSize: 18; color: rb.on ? "#ffffff" : root.fg }
    MouseArea { id: rbMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rb.clicked() }
  }

  // Page header: back chevron, title, optional switch.
  component Header: Item {
    id: hd
    property string title: ""
    property bool hasSwitch: false
    property bool switchOn: false
    property string busyText: ""
    property string photo: ""
    signal switched()
    width: root.innerWidth
    height: 34
    Rectangle {
      id: backBtn
      width: 30
      height: 30
      radius: 15
      anchors.verticalCenter: parent.verticalCenter
      color: backMouse.containsMouse ? root.tileHover : root.tileOff
      Glyph { anchors.centerIn: parent; text: "󰅁"; font.pixelSize: 16 }
      MouseArea { id: backMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.back() }
    }
    Artwork {
      id: hdFace
      anchors.left: backBtn.right
      anchors.leftMargin: 10
      anchors.verticalCenter: parent.verticalCenter
      visible: hd.photo !== ""
      width: visible ? 26 : 0
      height: 26
      radius: 13
      source: hd.photo
      fallbackColor: root.tileOff
    }
    Label {
      anchors.left: hdFace.visible ? hdFace.right : backBtn.right
      anchors.leftMargin: 10
      // A long chat name has to stop at the panel edge, not run past it.
      anchors.right: busyLabel.left
      anchors.rightMargin: 8
      anchors.verticalCenter: parent.verticalCenter
      text: hd.title
      elide: Text.ElideRight
      font.pixelSize: 16
      font.weight: Font.Bold
    }
    Label { id: busyLabel; anchors.right: sw.visible ? sw.left : parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: hd.busyText; font.pixelSize: 11; color: root.dim }
    Switch { id: sw; visible: hd.hasSwitch; on: hd.switchOn; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; onToggled: hd.switched() }
  }

  component Switch: Rectangle {
    id: swc
    property bool on: false
    signal toggled()
    width: 44
    height: 26
    radius: 13
    color: on ? root.onColor("green") : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.2)
    Behavior on color { ColorAnimation { duration: 160 } }
    Rectangle {
      width: 22
      height: 22
      radius: 11
      y: 2
      x: swc.on ? swc.width - width - 2 : 2
      color: "#ffffff"
      Behavior on x { SpringAnimation { spring: 5; damping: 0.4; epsilon: 0.1 } }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: swc.toggled() }
  }

  component SectionTitle: Label {
    width: root.innerWidth
    font.pixelSize: 11
    font.weight: Font.DemiBold
    font.letterSpacing: 0.6
    color: root.dim
    topPadding: 4
  }

  // List row used by every detail page.
  component Row2: Rectangle {
    id: row
    property string glyph: ""
    property string photo: ""
    property string title: ""
    property string subtitle: ""
    property bool selected: false
    property bool busy: false
    property string trailing: ""
    property bool canRemove: false
    signal clicked()
    signal removed()
    width: root.innerWidth
    height: 44
    radius: 14
    color: rowMouse.containsMouse ? root.tileOff : "transparent"
    MouseArea { id: rowMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: row.clicked() }
    Artwork {
      id: rowIcon
      x: 6
      anchors.verticalCenter: parent.verticalCenter
      width: 30
      height: 30
      radius: 15
      source: row.photo
      fallbackGlyph: row.glyph
      glyphFont: root.s.iconFont
      glyphColor: row.selected ? "#ffffff" : root.fg
      fallbackColor: row.selected ? root.onColor("blue") : root.tileOff
    }
    Column {
      anchors.left: rowIcon.right
      anchors.leftMargin: 10
      anchors.right: trail.left
      anchors.rightMargin: 8
      anchors.verticalCenter: parent.verticalCenter
      Label { width: parent.width; text: row.title; font.weight: row.selected ? Font.DemiBold : Font.Normal }
      Label { width: parent.width; text: row.subtitle; visible: text !== ""; font.pixelSize: 11; color: root.dim }
    }
    Row {
      id: trail
      anchors.right: parent.right
      anchors.rightMargin: 8
      anchors.verticalCenter: parent.verticalCenter
      spacing: 6
      Label { anchors.verticalCenter: parent.verticalCenter; text: row.busy ? "…" : row.trailing; font.pixelSize: 12; color: root.dim; font.family: text.length <= 2 ? root.s.iconFont : root.s.textFont }
      Rectangle {
        visible: row.canRemove && rowMouse.containsMouse || (row.canRemove && removeMouse.containsMouse)
        anchors.verticalCenter: parent.verticalCenter
        width: 24
        height: 24
        radius: 12
        color: removeMouse.containsMouse ? Qt.rgba(1, 0.27, 0.23, 0.25) : root.tileOff
        Glyph { anchors.centerIn: parent; text: "󰅖"; font.pixelSize: 12; color: root.dim }
        MouseArea { id: removeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: row.removed() }
      }
    }
  }

  // A page that scrolls when its list is longer than the island allows.
  component Scroller: Flickable {
    width: root.innerWidth
    clip: true
    contentWidth: width
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height
  }

  // ================================================================ pages
  Item {
    id: stage
    x: root.pad
    y: root.pad
    width: root.innerWidth
    height: parent.height - root.pad * 2

    // ------------------------------------------------ main
    Column {
      id: mainPage
      visible: opacity > 0.01
      opacity: root.page === "main" ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 160 } }
      width: parent.width
      spacing: 10

      // Date and time on the left; notifications, calendar and updates on the right.
      Item {
        width: parent.width
        height: 40
        Column {
          anchors.verticalCenter: parent.verticalCenter
          Label { text: root.s.clockText; font.pixelSize: 22; font.weight: Font.Bold; font.features: { "tnum": 1 } }
          Label { text: Qt.formatDateTime(root.s.now, "dddd, d MMMM") + (root.s.weatherText ? "  ·  " + root.s.weatherText : ""); font.pixelSize: 11; color: root.dim }
        }
        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: 8
          Rectangle {
            visible: root.s.updateAvailable
            width: updText.implicitWidth + 24
            height: 30
            radius: 15
            color: root.onColor("blue")
            Label { id: updText; anchors.centerIn: parent; text: "󰚰  Update"; color: "#ffffff"; font.pixelSize: 12; font.weight: Font.DemiBold; font.family: root.s.iconFont }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.win.closeControls(); root.s.runUpdate() } }
          }
          Round {
            width: 34; height: 34
            glyph: root.s.dnd ? "󰂛" : "󰂚"
            onClicked: root.go("notifications")
            Rectangle {
              visible: root.s.history.length > 0
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: -2
              width: Math.max(16, badge.implicitWidth + 8)
              height: 16
              radius: 8
              color: root.onColor("red")
              Label { id: badge; anchors.centerIn: parent; text: root.s.history.length > 99 ? "99+" : root.s.history.length; font.pixelSize: 10; font.weight: Font.Bold; color: "#ffffff" }
            }
          }
          Round { width: 34; height: 34; glyph: "󰃭"; onClicked: root.go("calendar") }
        }
      }

      Grid {
        columns: 2
        spacing: 10
        Tile {
          glyph: !root.wifiOn ? "󰤮" : root.wired && !root.wifiCurrent ? "󰈀" : root.wifiCurrent ? root.wifiGlyph(root.wifiCurrent.signal) : "󰤯"
          title: "Wi-Fi"
          subtitle: !root.wifiOn ? (root.wired ? "Ethernet" : "Off") : root.wifiCurrent ? root.wifiCurrent.ssid : root.wired ? "Ethernet" : "Not connected"
          on: root.wifiOn
          onToggled: root.toggleWifi()
          onOpened: root.go("wifi")
        }
        Tile {
          glyph: root.btOn ? "󰂯" : "󰂲"
          title: "Bluetooth"
          subtitle: !root.btOn ? "Off" : root.btConnected.length === 1 ? root.btName(root.btConnected[0])
            : root.btConnected.length > 1 ? root.btConnected.length + " devices" : "On"
          on: root.btOn
          onToggled: root.toggleBluetooth()
          onOpened: root.go("bluetooth")
        }
        Tile {
          visible: root.hasBuds
          glyph: "󱡏"
          title: root.budsStatus && root.budsStatus.deviceName ? root.budsStatus.deviceName : "Earbuds"
          subtitle: !root.budsStatus || !root.budsStatus.connected ? "Not connected"
            : "L " + root.budsLevel(root.budsStatus.left) + " · R " + root.budsLevel(root.budsStatus.right) + " · " + (root.modeNames[root.budsStatus.noiseMode] || "")
          on: !!(root.budsStatus && root.budsStatus.connected)
          accent: root.onColor("blue")
          onToggled: root.buds.toggleConnection()
          onOpened: root.go("buds")
        }
        Tile {
          visible: root.hasPhone
          glyph: "󰄜"
          title: "Phone"
          subtitle: root.phoneRunning ? "Mirroring " + root.phoneName(root.phoneDevice)
            : root.phone && root.phone.hasReadyDevice ? root.phoneName(root.phoneDevice) + " · ready"
            : root.phone && root.phone.onlinePeer ? root.phone.onlinePeer.name + " · Tailscale" : "Not connected"
          on: root.phoneRunning
          accent: root.onColor("green")
          onToggled: root.togglePhone()
          onOpened: root.go("phone")
        }
        Tile {
          visible: !root.hasBuds || !root.hasPhone
          glyph: root.profileGlyph(root.powerProfile)
          title: "Power Mode"
          subtitle: root.profileLabel(root.powerProfile)
          on: root.powerProfile === "performance" || root.powerProfile === "power-saver"
          accent: root.powerProfile === "power-saver" ? root.onColor("yellow") : root.onColor("orange")
          chevron: false
          onToggled: root.cycleProfile()
          onOpened: root.cycleProfile()
        }
      }

      Item {
        width: parent.width
        height: 36
        FatSlider {
          anchors.left: parent.left
          anchors.right: audioBtn.left
          anchors.rightMargin: 8
          value: root.muted ? 0 : root.volume
          glyph: root.muted || root.volume <= 0 ? "󰝟" : root.volume < 0.34 ? "󰕿" : root.volume < 0.67 ? "󰖀" : "󰕾"
          onMoved: function(v) { root.setVolume(v) }
          onGlyphClicked: root.toggleMute()
        }
        Rectangle {
          id: audioBtn
          anchors.right: parent.right
          width: 36
          height: 36
          radius: 18
          color: audioMouse.containsMouse ? root.tileHover : root.tileOff
          Glyph { anchors.centerIn: parent; text: "󰓃"; font.pixelSize: 16 }
          MouseArea { id: audioMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.go("audio") }
        }
      }
      FatSlider {
        visible: root.brightness >= 0
        width: parent.width
        value: root.brightness
        glyph: root.brightness < 0.5 ? root.s.glyphs.brightLow : root.s.glyphs.brightHigh
        onMoved: function(v) { root.setBrightness(v) }
      }

      Row {
        spacing: Math.floor((root.innerWidth - 42 * visibleChildren.length) / Math.max(1, visibleChildren.length - 1))
        Round { glyph: root.s.glyphs.moon; on: root.s.dnd; accent: root.onColor("indigo"); onClicked: root.toggleDnd() }
        Round { glyph: "󰌵"; on: root.nightLight; accent: root.onColor("orange"); onClicked: root.toggleNight() }
        Round { glyph: "󰅶"; on: root.stayAwake; accent: root.onColor("yellow"); onClicked: root.toggleAwake() }
        Round { glyph: root.profileGlyph(root.powerProfile); visible: root.hasBuds && root.hasPhone; on: root.powerProfile !== "balanced" && root.powerProfile !== ""; accent: root.onColor("orange"); onClicked: root.cycleProfile() }
        Round { glyph: "󰄀"; onClicked: { root.win.closeControls(); root.run(["omarchy-capture-screenshot"], false) } }
        Round { glyph: root.s.glyphs.record; on: root.s.recording; accent: root.onColor("red"); onClicked: { root.win.closeControls(); root.run(root.s.recording ? ["omarchy-capture-screenrecording", "--stop-recording"] : ["omarchy-capture-screenrecording"], false) } }
        Round { glyph: "󰐥"; accent: root.onColor("red"); onClicked: root.go("power") }
      }

      // System tray: left click activates, right click opens the app's menu.
      Flow {
        visible: root.trayItems.length > 0
        width: parent.width
        spacing: 6
        Repeater {
          model: root.trayItems
          delegate: Rectangle {
            id: trayCell
            required property var modelData
            width: 34
            height: 34
            radius: 12
            color: trayMouse.containsMouse ? root.tileHover : root.tileOff
            Image {
              anchors.centerIn: parent
              width: 18
              height: 18
              sourceSize.width: 36
              sourceSize.height: 36
              source: trayCell.modelData.icon || ""
              smooth: true
            }
            QsMenuAnchor {
              id: trayMenu
              menu: trayCell.modelData.menu
              anchor.item: trayCell
              anchor.edges: Edges.Bottom
              anchor.gravity: Edges.Bottom
            }
            MouseArea {
              id: trayMouse
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
              cursorShape: Qt.PointingHandCursor
              onClicked: function(m) {
                var it = trayCell.modelData
                if (m.button === Qt.MiddleButton) it.secondaryActivate()
                else if (m.button === Qt.RightButton || it.onlyMenu) { if (it.hasMenu) trayMenu.open() }
                else it.activate()
              }
            }
          }
        }
      }
    }

    // ------------------------------------------------ Wi-Fi
    Column {
      id: wifiPage
      visible: opacity > 0.01
      opacity: root.page === "wifi" ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 160 } }
      width: parent.width
      spacing: 6

      Header {
        title: "Wi-Fi"
        hasSwitch: true
        switchOn: root.wifiOn
        busyText: root.wifiOn && root.wifiDevice && root.wifiDevice.scannerEnabled ? "Scanning" : ""
        onSwitched: root.toggleWifi()
      }
      Label { visible: !root.wifiOn; text: "Wi-Fi is off"; color: root.dim; topPadding: 6; bottomPadding: 6 }
      Label { visible: root.wifiOn && root.wifiRows.length === 0; text: "Looking for networks…"; color: root.dim; topPadding: 6; bottomPadding: 6 }
      Scroller {
        visible: root.wifiOn && root.wifiRows.length > 0
        height: Math.min(contentHeight, 360)
        contentHeight: wifiList.implicitHeight
        Column {
          id: wifiList
          width: parent.width
          spacing: 2
          Repeater {
            model: root.wifiRows
            delegate: Column {
              id: wifiCell
              required property var modelData
              width: root.innerWidth
              Row2 {
                glyph: root.wifiGlyph(wifiCell.modelData.signal)
                title: wifiCell.modelData.ssid
                subtitle: root.wifiFailSsid === wifiCell.modelData.ssid ? root.wifiFailText
                  : wifiCell.modelData.connected ? "Connected" : wifiCell.modelData.known ? "Saved" : ""
                selected: wifiCell.modelData.connected
                busy: root.wifiBusySsid === wifiCell.modelData.ssid
                trailing: wifiCell.modelData.secure ? "󰌾" : ""
                canRemove: wifiCell.modelData.known
                onClicked: root.wifiRowClicked(wifiCell.modelData)
                onRemoved: root.wifiForget(wifiCell.modelData.ssid)
              }
              // Inline password entry, like iOS's join sheet.
              Item {
                visible: root.passwordSsid === wifiCell.modelData.ssid
                width: parent.width
                height: visible ? 44 : 0
                Rectangle {
                  anchors.left: parent.left
                  anchors.leftMargin: 46
                  anchors.right: joinBtn.left
                  anchors.rightMargin: 8
                  anchors.verticalCenter: parent.verticalCenter
                  height: 34
                  radius: 12
                  color: root.tileOff
                  border.width: pass.activeFocus ? 1 : 0
                  border.color: root.onColor("blue")
                  TextInput {
                    id: pass
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password
                    font.family: root.s.textFont
                    font.pixelSize: 13
                    color: root.fg
                    selectionColor: root.onColor("blue")
                    clip: true
                    focus: visible
                    onVisibleChanged: { text = ""; if (visible) Qt.callLater(function() { pass.forceActiveFocus() }) }
                    Keys.onReturnPressed: root.wifiConnectWithPassword(wifiCell.modelData.ssid, text)
                    Keys.onEnterPressed: root.wifiConnectWithPassword(wifiCell.modelData.ssid, text)
                    Keys.onEscapePressed: root.cancelPassword()
                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      visible: pass.text === ""
                      text: "Password"
                      font: pass.font
                      color: root.dim
                    }
                  }
                }
                Rectangle {
                  id: joinBtn
                  anchors.right: parent.right
                  anchors.rightMargin: 6
                  anchors.verticalCenter: parent.verticalCenter
                  width: 64
                  height: 34
                  radius: 17
                  color: root.onColor("blue")
                  opacity: pass.text !== "" ? 1 : 0.45
                  Label { anchors.centerIn: parent; text: "Join"; color: "#ffffff"; font.weight: Font.DemiBold }
                  MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.wifiConnectWithPassword(wifiCell.modelData.ssid, pass.text) }
                }
              }
            }
          }
        }
      }
    }

    // ------------------------------------------------ Bluetooth
    Column {
      id: btPage
      visible: opacity > 0.01
      opacity: root.page === "bluetooth" ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 160 } }
      width: parent.width
      spacing: 6

      Header {
        title: "Bluetooth"
        hasSwitch: true
        switchOn: root.btOn
        busyText: root.btOn && root.btAdapter && root.btAdapter.discovering ? "Searching" : ""
        onSwitched: root.toggleBluetooth()
      }
      Label { visible: !root.btOn; text: "Bluetooth is off"; color: root.dim; topPadding: 6; bottomPadding: 6 }
      Scroller {
        visible: root.btOn
        height: Math.min(contentHeight, 380)
        contentHeight: btList.implicitHeight
        Column {
          id: btList
          width: parent.width
          spacing: 2
          SectionTitle { text: "MY DEVICES"; visible: root.btRows.known.length > 0 }
          Repeater {
            model: root.btRows.known
            delegate: Row2 {
              required property var modelData
              glyph: root.btGlyph(modelData.icon)
              title: modelData.name
              subtitle: root.btPending[modelData.address] ? (root.btPending[modelData.address].charAt(0).toUpperCase() + root.btPending[modelData.address].slice(1) + "…")
                : modelData.connected ? "Connected" + (modelData.battery >= 0 ? " · " + modelData.battery + "%" : "") : "Not connected"
              selected: modelData.connected
              busy: !!root.btPending[modelData.address]
              canRemove: true
              onClicked: root.btClick(modelData)
              onRemoved: root.btForget(modelData)
            }
          }
          SectionTitle { text: "OTHER DEVICES"; visible: root.btRows.found.length > 0 }
          Repeater {
            model: root.btRows.found
            delegate: Row2 {
              required property var modelData
              glyph: root.btGlyph(modelData.icon)
              title: modelData.name
              subtitle: root.btPending[modelData.address] ? "Pairing…" : "Tap to pair"
              busy: !!root.btPending[modelData.address]
              onClicked: root.btClick(modelData)
            }
          }
          Label { visible: root.btRows.found.length === 0; text: "Looking for devices…"; color: root.dim; font.pixelSize: 12; topPadding: 6; bottomPadding: 4 }
        }
      }
    }

    // ------------------------------------------------ sound
    Column {
      id: audioPage
      visible: opacity > 0.01
      opacity: root.page === "audio" ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 160 } }
      width: parent.width
      spacing: 6

      Header { title: "Sound" }
      FatSlider {
        width: parent.width
        value: root.muted ? 0 : root.volume
        glyph: root.muted ? "󰝟" : "󰕾"
        onMoved: function(v) { root.setVolume(v) }
        onGlyphClicked: root.toggleMute()
      }
      Scroller {
        height: Math.min(contentHeight, 340)
        contentHeight: audioList.implicitHeight
        Column {
          id: audioList
          width: parent.width
          spacing: 2
          SectionTitle { text: "OUTPUT" }
          Repeater {
            model: root.sinks
            delegate: Row2 {
              required property var modelData
              glyph: String(modelData.name || "").indexOf("bluez") !== -1 ? "󰋋" : String(modelData.name || "").indexOf("hdmi") !== -1 ? "󰡁" : "󰓃"
              title: root.nodeName(modelData)
              selected: root.sink && modelData.id === root.sink.id
              trailing: selected ? "󰄬" : ""
              onClicked: root.setSink(modelData)
            }
          }
          SectionTitle { text: "INPUT" }
          Repeater {
            model: root.sources
            delegate: Row2 {
              required property var modelData
              glyph: "󰍬"
              title: root.nodeName(modelData)
              selected: root.source && modelData.id === root.source.id
              trailing: selected ? "󰄬" : ""
              onClicked: root.setSource(modelData)
            }
          }
          Row2 {
            glyph: root.micMuted ? "󰍭" : "󰍬"
            title: root.micMuted ? "Microphone muted" : "Microphone on"
            subtitle: "Tap to " + (root.micMuted ? "unmute" : "mute")
            selected: !root.micMuted
            onClicked: root.toggleMic()
          }
        }
      }
    }

    // ------------------------------------------------ earbuds
    Column {
      id: budsPage
      visible: opacity > 0.01
      opacity: root.page === "buds" ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 160 } }
      width: parent.width
      spacing: 10

      Header {
        title: root.budsStatus && root.budsStatus.deviceName ? root.budsStatus.deviceName : "Earbuds"
        hasSwitch: root.hasBuds
        switchOn: !!(root.budsStatus && root.budsStatus.connected)
        busyText: root.buds && root.buds.connectionRequest !== "" ? (root.buds.connectionRequest === "connect" ? "Connecting" : "Disconnecting")
          : root.buds && root.buds.actionStatus ? root.buds.actionStatus : ""
        onSwitched: root.buds.toggleConnection()
      }
      // Battery: left, right, case — like the AirPods card.
      Row {
        visible: !!root.budsStatus
        spacing: 10
        Repeater {
          model: root.budsStatus ? [["Left", root.budsStatus.left], ["Right", root.budsStatus.right], ["Case", root.budsStatus.caseBattery]] : []
          delegate: Rectangle {
            required property var modelData
            width: (root.innerWidth - 20) / 3
            height: 62
            radius: 18
            color: root.tileOff
            Column {
              anchors.centerIn: parent
              spacing: 4
              Label { anchors.horizontalCenter: parent.horizontalCenter; text: (modelData[1].charging ? "󱐋 " : "") + root.budsLevel(modelData[1]); font.pixelSize: 17; font.weight: Font.DemiBold
                color: modelData[1].level >= 0 && modelData[1].level <= 20 ? root.onColor("red") : root.fg }
              Label { anchors.horizontalCenter: parent.horizontalCenter; text: modelData[0]; font.pixelSize: 11; color: root.dim }
            }
          }
        }
      }
      SectionTitle { text: "NOISE CONTROL"; visible: !!(root.budsStatus && root.budsStatus.linked) }
      Row {
        visible: !!(root.budsStatus && root.budsStatus.linked)
        spacing: 8
        Repeater {
          model: root.budsStatus ? root.budsStatus.modes : []
          delegate: Rectangle {
            required property var modelData
            readonly property bool sel: root.budsStatus.noiseMode === modelData
            width: (root.innerWidth - 8 * (root.budsStatus.modes.length - 1)) / Math.max(1, root.budsStatus.modes.length)
            height: 58
            radius: 18
            color: sel ? root.onColor("blue") : modeMouse.containsMouse ? root.tileHover : root.tileOff
            Behavior on color { ColorAnimation { duration: 140 } }
            Column {
              anchors.centerIn: parent
              spacing: 3
              Glyph { anchors.horizontalCenter: parent.horizontalCenter; text: root.modeGlyphs[modelData] || "󰋋"; font.pixelSize: 18; color: sel ? "#ffffff" : root.fg }
              Label { anchors.horizontalCenter: parent.horizontalCenter; text: root.modeNames[modelData] || modelData; font.pixelSize: 10; color: sel ? "#ffffff" : root.dim }
            }
            MouseArea { id: modeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.buds.setNoiseMode(modelData) }
          }
        }
      }
      Row {
        visible: !!(root.budsStatus && root.budsStatus.linked && root.budsStatus.noiseMode === "anc" && root.budsStatus.levels.length > 0)
        spacing: 6
        Repeater {
          model: root.budsStatus ? root.budsStatus.levels : []
          delegate: Rectangle {
            required property var modelData
            readonly property bool sel: root.budsStatus.ancLevel === modelData
            width: (root.innerWidth - 6 * (root.budsStatus.levels.length - 1)) / Math.max(1, root.budsStatus.levels.length)
            height: 30
            radius: 15
            color: sel ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.9) : root.tileOff
            Label { anchors.centerIn: parent; text: modelData.charAt(0).toUpperCase() + modelData.slice(1); font.pixelSize: 12; color: sel ? "#000000" : root.fg }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.buds.setAncLevel(modelData) }
          }
        }
      }
      SectionTitle { text: "SOUND"; visible: !!(root.budsStatus && root.budsStatus.linked && root.budsStatus.eqPresets.length > 0) }
      Flow {
        visible: !!(root.budsStatus && root.budsStatus.linked)
        width: parent.width
        spacing: 6
        Repeater {
          model: root.budsStatus ? root.budsStatus.eqPresets : []
          delegate: Rectangle {
            required property var modelData
            readonly property bool sel: root.budsStatus.eq === modelData.id
            width: eqText.implicitWidth + 24
            height: 30
            radius: 15
            color: sel ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.9) : root.tileOff
            Label { id: eqText; anchors.centerIn: parent; text: modelData.name; font.pixelSize: 12; color: sel ? "#000000" : root.fg }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.buds.setEq(modelData.id) }
          }
        }
      }
      Repeater {
        model: root.budsStatus && root.budsStatus.linked ? root.budsStatus.featureList : []
        delegate: Item {
          required property var modelData
          width: root.innerWidth
          height: 32
          Label { anchors.verticalCenter: parent.verticalCenter; text: ({ wear: "Wear detection", game: "Game mode", spatial: "Spatial audio" })[modelData] || modelData }
          Switch {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            on: !!root.budsStatus.features[modelData]
            onToggled: root.buds.setFeature(modelData, !on)
          }
        }
      }
      Label {
        visible: !!(root.budsStatus && root.budsStatus.firmware)
        width: root.innerWidth
        horizontalAlignment: Text.AlignHCenter
        text: root.budsStatus ? (root.budsStatus.modelName || "") + " · firmware " + root.budsStatus.firmware : ""
        font.pixelSize: 10
        color: root.dim
      }
      Label { visible: !!(root.budsStatus && !root.budsStatus.connected); text: "Take the buds out of the case and turn the switch on."; color: root.dim; font.pixelSize: 12; width: root.innerWidth; wrapMode: Text.WordWrap }
    }

    // ------------------------------------------------ phone (Taildroid)
    Column {
      id: phonePage
      visible: opacity > 0.01
      opacity: root.page === "phone" ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 160 } }
      width: parent.width
      spacing: 6

      Header {
        title: "Phone"
        hasSwitch: root.hasPhone
        switchOn: root.phoneRunning
        busyText: root.phone && root.phone.refreshing ? "Checking" : root.phone && root.phone.busy ? "Working" : ""
        onSwitched: root.togglePhone()
      }

      // Continuity: the phone at a glance, then one tap to everything.
      Row2 {
        visible: root.hasPhone
        glyph: "󰄜"
        title: root.psPhone.model || root.psKde.name || root.psBt.name || "Galaxy S24"
        subtitle: root.phoneLinkText()
        selected: !!root.psPhone.serial || !!root.psKde.reachable
        trailing: root.phoneRunning ? "Mirroring" : ""
        onClicked: root.togglePhone()
      }
      Row {
        visible: root.hasPhone
        spacing: (root.innerWidth - 42 * 8) / 7
        Round { glyph: "󰏲"; hint: "Call"; onClicked: root.go("call") }
        Round { glyph: "󰍡"; hint: "Messages"; onClicked: { root.go("messages"); root.phone.refreshPhone() } }
        Round { glyph: "󰉏"; hint: "Photos"; onClicked: root.phone.photos() }
        Round { glyph: "󰍹"; hint: "DeX"; onClicked: root.phone.openDex() }
        Round { glyph: "󰄀"; hint: "Webcam"; onClicked: root.phone.webcam() }
        Round { glyph: "󰅌"; hint: "Send clipboard"; onClicked: root.phone.sendClipboard() }
        Round { glyph: "󰀂"; hint: "Hotspot"; on: !!root.ps.hotspot; accent: root.onColor("green"); onClicked: root.phone.phonedSend({ cmd: "hotspot" }) }
        Round { glyph: "\u{F009E}"; hint: "Find phone"; accent: root.onColor("orange"); onClicked: root.phone.ring() }
      }
      Label {
        visible: root.hasPhone
        width: root.innerWidth
        wrapMode: Text.WordWrap
        font.pixelSize: 11
        color: root.dim
        text: (root.callsReady ? "Calls: ready on this PC." : root.psBt.paired ? "Calls: waiting for the phone's Bluetooth link." : "Calls: pair the phone in Bluetooth settings (allow calls).")
          + "  " + (!root.psKde.running ? "Messages: install KDE Connect." : !root.psKde.deviceId ? "Messages: open KDE Connect on the phone and pair." : !root.psKde.reachable ? "Messages: phone not reachable." : "Messages: ready.")
      }
      Rectangle {
        visible: !!(root.hasPhone && root.psKde.running && !root.psKde.deviceId)
        width: root.innerWidth
        height: 32
        radius: 16
        color: root.onColor("blue")
        Label { anchors.centerIn: parent; text: "Pair with KDE Connect"; color: "#ffffff"; font.weight: Font.DemiBold }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.phone.pairKdeconnect() }
      }
      Label {
        width: root.innerWidth
        visible: text !== ""
        wrapMode: Text.WordWrap
        maximumLineCount: 3
        text: !root.phone ? "Install Taildroid to mirror your Android phone."
          : root.phone.actionStatus !== "" ? root.phone.actionStatus
          : root.phone.lastError !== "" ? root.phone.lastError : root.phone.statusText
        font.pixelSize: 12
        color: root.phone && root.phone.lastError !== "" && root.phone.actionStatus === "" ? root.onColor("red") : root.dim
      }
      Scroller {
        visible: root.hasPhone
        height: Math.min(contentHeight, 380)
        contentHeight: phoneList.implicitHeight
        Column {
          id: phoneList
          width: parent.width
          spacing: 2
          Row2 {
            visible: !!(root.phone && root.phone.onlinePeer)
            glyph: "󰖂"
            title: root.phone && root.phone.onlinePeer ? "Connect " + root.phone.onlinePeer.name + " over Tailscale" : ""
            subtitle: "ADB over Tailscale, port " + (root.phone ? root.phone.adbPort : 5555)
            onClicked: root.phone.connectTailscale()
          }
          SectionTitle { text: "DEVICES"; visible: root.phone && root.phone.devices.length > 0 }
          Repeater {
            model: root.phone ? root.phone.devices : []
            delegate: Row2 {
              required property var modelData
              glyph: modelData.transport === "tcp" ? "󰖩" : "󰕓"
              title: root.phoneName(modelData)
              subtitle: root.phoneSub(modelData)
              selected: root.phoneRunning && root.phone.controllingSerial === modelData.serial
              trailing: modelData.state === "device" ? (selected ? "Stop" : "Mirror") : ""
              canRemove: modelData.transport === "tcp"
              onClicked: {
                if (selected) root.phone.stopControl()
                else if (modelData.state === "device") root.phone.startControl(modelData)
              }
              onRemoved: root.phone.disconnectDevice(modelData.serial)
            }
          }
          SectionTitle { text: "TAILSCALE"; visible: root.phone && root.phone.tailscalePeers.length > 0 }
          Repeater {
            model: root.phone ? root.phone.tailscalePeers : []
            delegate: Row2 {
              required property var modelData
              glyph: "󰏲"
              title: modelData.name || "Android"
              subtitle: (modelData.online ? "Online" : "Offline") + (modelData.ip ? " · " + modelData.ip : "")
              selected: !!modelData.online
              onClicked: if (modelData.ip) root.phone.connectAddress(modelData.ip + ":" + root.phone.adbPort)
            }
          }
          // Wireless debugging pairing: address and the six-digit code.
          SectionTitle { text: "PAIR WIRELESS DEBUGGING" }
          Row {
            spacing: 6
            Repeater {
              model: [["pairAddress", "192.168.1.5:37000", 200], ["pairCode", "Code", 100]]
              delegate: Rectangle {
                required property var modelData
                width: modelData[2]
                height: 34
                radius: 12
                color: root.tileOff
                border.width: field.activeFocus ? 1 : 0
                border.color: root.onColor("blue")
                TextInput {
                  id: field
                  anchors.fill: parent
                  anchors.leftMargin: 12
                  anchors.rightMargin: 12
                  verticalAlignment: TextInput.AlignVCenter
                  font.family: root.s.textFont
                  font.pixelSize: 13
                  color: root.fg
                  clip: true
                  text: root[modelData[0]]
                  onTextEdited: root[modelData[0]] = text
                  Keys.onReturnPressed: root.phone.pair(root.pairAddress, root.pairCode)
                  Keys.onEscapePressed: root.back()
                  Text { anchors.verticalCenter: parent.verticalCenter; visible: field.text === ""; text: modelData[1]; font: field.font; color: root.dim }
                }
              }
            }
            Rectangle {
              width: root.innerWidth - 306 - 12
              height: 34
              radius: 17
              color: root.onColor("blue")
              opacity: root.pairAddress !== "" && root.pairCode !== "" ? 1 : 0.45
              Label { anchors.centerIn: parent; text: "Pair"; color: "#ffffff"; font.weight: Font.DemiBold }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.phone.pair(root.pairAddress, root.pairCode); root.pairCode = "" } }
            }
          }
          Label {
            width: root.innerWidth
            topPadding: 6
            wrapMode: Text.WordWrap
            text: "Phone: Developer options › Wireless debugging › Pair with code. While mirroring, press Left Alt or Super to give the mouse back."
            font.pixelSize: 11
            color: root.dim
          }
        }
      }
    }

    // ------------------------------------------------ call / dialer
    Column {
      id: callPage
      visible: opacity > 0.01
      opacity: root.page === "call" ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 160 } }
      width: parent.width
      spacing: 10

      Header { title: root.call ? "Call" : "Keypad"; busyText: root.callsReady ? root.s.phoneName : "Bluetooth not linked" }

      Column {
        visible: !!root.call
        width: root.innerWidth
        spacing: 2
        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          width: 64; height: 64; radius: 32
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.14)
          Label {
            anchors.centerIn: parent
            text: root.call && root.call.name ? root.call.name.charAt(0).toUpperCase() : "?"
            font.pixelSize: 26
            font.weight: Font.DemiBold
          }
        }
        Label { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: root.s.callTitle(root.call); font.pixelSize: 18; font.weight: Font.DemiBold }
        Label {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: root.call ? ((root.call.name ? root.call.number + " · " : "") + (root.call.state === "incoming" ? "Incoming" : root.s.callElapsed(root.call))) : ""
          font.pixelSize: 12
          color: root.dim
        }
      }

      // Number being dialed.
      Label {
        visible: !root.call
        width: root.innerWidth
        horizontalAlignment: Text.AlignHCenter
        text: root.dialNumber !== "" ? root.dialNumber : "Enter a number"
        color: root.dialNumber !== "" ? root.fg : root.dim
        id: dialLabel
        font.pixelSize: 24
        font.weight: Font.Medium
        Keys.onPressed: function(e) {
          if (/^[0-9*#+]$/.test(e.text)) { root.keypadPress(e.text); e.accepted = true }
          else if (e.key === Qt.Key_Backspace) { root.dialNumber = root.dialNumber.slice(0, -1); e.accepted = true }
          else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { if (!root.call) root.phone.dial(root.dialNumber); e.accepted = true }
          else if (e.key === Qt.Key_V && (e.modifiers & Qt.ControlModifier)) { pasteNumber.running = true; e.accepted = true }
        }
      }

      Grid {
        visible: !root.call || root.keypadInCall
        anchors.horizontalCenter: parent.horizontalCenter
        columns: 3
        spacing: 10
        Repeater {
          model: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#"]
          delegate: Rectangle {
            required property string modelData
            width: 58; height: 44; radius: 22
            color: keyMouse.pressed ? root.tileHover : root.tileOff
            Label { anchors.centerIn: parent; text: modelData; font.pixelSize: 19; font.weight: Font.Medium }
            MouseArea { id: keyMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.keypadPress(modelData) }
          }
        }
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 14
        Round { visible: !!root.call && root.call.state !== "incoming"; glyph: root.phone && root.phone.micMuted ? "󰍭" : "󰍬"; on: !!(root.phone && root.phone.micMuted); accent: root.onColor("red"); onClicked: root.phone.toggleMute() }
        Round { visible: !!root.call && root.call.state !== "incoming"; glyph: "󰌌"; on: root.keypadInCall; onClicked: root.keypadInCall = !root.keypadInCall }
        Round { visible: !!root.call && root.s.phoneCalls.length > 1; glyph: "󰓡"; onClicked: root.phone.swapCalls() }
        Round { visible: !!root.call && root.call.state !== "incoming"; glyph: "󰕾"; onClicked: root.go("audio") }
        Round { visible: !root.call && root.dialNumber !== ""; glyph: "󰭜"; onClicked: root.dialNumber = root.dialNumber.slice(0, -1) }
        Round { visible: !!root.call && root.call.state === "incoming"; glyph: "󰏲"; on: true; accent: root.onColor("green"); onClicked: root.phone.answer(root.call.path) }
        Round {
          glyph: root.call ? "󰏷" : "󰏲"
          on: true
          accent: root.call ? root.onColor("red") : root.onColor("green")
          onClicked: root.call ? root.phone.hangup(root.call.path) : root.phone.dial(root.dialNumber)
        }
      }
      Label {
        visible: !root.callsReady
        width: root.innerWidth
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: 11
        color: root.dim
        text: "Pair the phone with this PC over Bluetooth to hear calls here. Without it, calls are placed on the phone."
      }
    }

    // ------------------------------------------------ messages
    Column {
      id: messagesPage
      visible: opacity > 0.01
      opacity: root.page === "messages" ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 160 } }
      width: parent.width
      spacing: 6

      Header { title: "Messages"; busyText: root.psKde.reachable ? (root.psKde.name || "") : "Phone not reachable" }
      Row2 { glyph: "󰏫"; title: "New Message"; onClicked: root.openThread(null) }
      Label {
        visible: root.allChats.length === 0
        width: root.innerWidth
        wrapMode: Text.WordWrap
        font.pixelSize: 12
        color: root.dim
        text: !root.psKde.running ? "Messages need KDE Connect on this PC and on the phone." : "No conversations yet — allow SMS permission in KDE Connect on the phone."
      }
      Scroller {
        height: Math.min(contentHeight, 400)
        contentHeight: threadList.implicitHeight
        Column {
          id: threadList
          width: parent.width
          spacing: 2
          Repeater {
            model: root.allChats
            delegate: Row2 {
              required property var modelData
              glyph: "󰍡"
              photo: modelData.face ? "file://" + modelData.face : ""
              selected: modelData.unread
              title: modelData.name
              subtitle: (modelData.kind === "chat" ? modelData.app : "SMS") + " · "
                + (modelData.outgoing ? "You: " : "") + String(modelData.body).replace(/\s+/g, " ")
              trailing: root.s.timeAgo(modelData.date)
              onClicked: root.openThread(modelData)
            }
          }
        }
      }
    }

    // ------------------------------------------------ one conversation
    Column {
      id: threadPage
      visible: opacity > 0.01
      opacity: root.page === "thread" ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 160 } }
      width: parent.width
      spacing: 8

      Header {
        title: root.threadInfo.name || "Message"
        photo: root.threadInfo.face ? "file://" + root.threadInfo.face : ""
        busyText: root.threadInfo.kind === "chat" ? root.threadInfo.app : ""
      }
      Rectangle {
        visible: root.threadInfo.isNew === true
        width: root.innerWidth
        height: 34
        radius: 12
        color: root.tileOff
        TextInput {
          id: toField
          anchors.fill: parent
          anchors.leftMargin: 12
          anchors.rightMargin: 12
          verticalAlignment: TextInput.AlignVCenter
          font.family: root.s.textFont
          font.pixelSize: 13
          color: root.fg
          text: root.newRecipient
          onTextEdited: root.newRecipient = text
          Keys.onEscapePressed: root.back()
          Text { anchors.verticalCenter: parent.verticalCenter; visible: toField.text === ""; text: "To: phone number"; font: toField.font; color: root.dim }
        }
      }
      ListView {
        id: bubbles
        width: root.innerWidth
        height: root.threadInfo.isNew === true ? 60 : 460
        clip: true
        spacing: 6
        // The message that opened the thread shows at once; history follows from the phone.
        model: root.threadMsgs
        onCountChanged: Qt.callLater(function() { bubbles.positionViewAtEnd() })
        delegate: Item {
          id: msg
          required property var modelData
          // Pictures come from the phone one file at a time; until one lands the
          // bubble still has to say the message carried something.
          readonly property var atts: modelData.attachments || []
          readonly property var paths: modelData.files || []
          readonly property int pending: msg.atts.length - msg.paths.filter(function(f) { return f !== "" }).length
          readonly property bool out: !!modelData.outgoing
          width: bubbles.width
          height: bubble.height
          Rectangle {
            id: bubble
            anchors.right: msg.out ? parent.right : undefined
            width: Math.min(bubbles.width * 0.78, bubbleCol.width + 24)
            height: bubbleCol.implicitHeight + 14
            radius: 16
            color: msg.out ? root.onColor("blue") : root.tileOff
            Column {
              id: bubbleCol
              x: 12
              y: 7
              spacing: 6
              width: Math.min(bubbles.width * 0.78 - 24,
                              Math.max(bubbleText.implicitWidth, timeText.implicitWidth,
                                       msg.atts.length > 0 ? 230 : 0))
              Repeater {
                model: msg.atts
                delegate: Column {
                  required property int index
                  required property var modelData
                  readonly property string file: String(msg.paths[index] || "")
                  readonly property string mime: String(modelData.mime || "")
                  width: bubbleCol.width
                  spacing: 4
                  Image {
                    visible: parent.file !== "" && parent.mime.indexOf("image/") === 0
                    source: visible ? "file://" + parent.file : ""
                    width: bubbleCol.width
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: false
                  }
                  // Voice notes, video, anything else: hand it to the desktop.
                  Rectangle {
                    visible: parent.file !== "" && parent.mime.indexOf("image/") !== 0
                    width: bubbleCol.width
                    height: visible ? 34 : 0
                    radius: 17
                    color: msg.out ? Qt.rgba(1, 1, 1, 0.18) : root.tileHover
                    Glyph {
                      id: playGlyph
                      x: 10
                      anchors.verticalCenter: parent.verticalCenter
                      text: parent.parent.mime.indexOf("audio/") === 0 ? "\U000f040a" : "\U000f0220"
                      font.pixelSize: 14
                      color: msg.out ? "#ffffff" : root.fg
                    }
                    Label {
                      anchors.left: playGlyph.right
                      anchors.leftMargin: 8
                      anchors.right: parent.right
                      anchors.rightMargin: 10
                      anchors.verticalCenter: parent.verticalCenter
                      text: parent.parent.mime.indexOf("audio/") === 0 ? "Voice message" : parent.parent.mime
                      elide: Text.ElideRight
                      font.pixelSize: 12
                      color: msg.out ? "#ffffff" : root.fg
                    }
                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: Quickshell.execDetached(["xdg-open", parent.parent.file])
                    }
                  }
                }
              }
              Label {
                id: bubbleText
                width: bubbleCol.width
                visible: text !== ""
                text: String(msg.modelData.body || "") || (msg.pending > 0 ? "📎 Attachment" : "")
                wrapMode: Text.Wrap
                font.pixelSize: 13
                color: msg.out ? "#ffffff" : root.fg
                textFormat: Text.PlainText
              }
              Label {
                id: timeText
                width: bubbleCol.width
                horizontalAlignment: Text.AlignRight
                visible: msg.modelData.date > 0
                text: Qt.formatDateTime(new Date(msg.modelData.date), "HH:mm")
                font.pixelSize: 10
                color: msg.out ? Qt.rgba(1, 1, 1, 0.7) : root.dim
              }
            }
          }
        }
      }
      Row {
        spacing: 8
        Rectangle {
          width: root.innerWidth - 42
          height: 36
          radius: 18
          color: root.tileOff
          TextInput {
            id: draftField
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            verticalAlignment: TextInput.AlignVCenter
            font.family: root.s.textFont
            font.pixelSize: 13
            color: root.fg
            clip: true
            text: root.draft
            onTextEdited: root.draft = text
            Keys.onReturnPressed: root.sendDraft()
            Keys.onEscapePressed: root.back()
            readonly property bool canSend: root.threadInfo.kind !== "chat" || root.threadInfo.replyId !== ""
            enabled: draftField.canSend
            Text {
              anchors.verticalCenter: parent.verticalCenter
              visible: draftField.text === ""
              text: draftField.canSend
                ? (root.threadInfo.kind === "chat" ? "Reply on " + root.threadInfo.app : "Text Message")
                : "This chat can only be answered while its notification is live"
              font: draftField.font
              color: root.dim
              width: parent.width
              elide: Text.ElideRight
            }
          }
        }
        Round { width: 36; height: 36; glyph: "󰒊"; on: root.draft.trim() !== "" && draftField.canSend; onClicked: root.sendDraft() }
      }
    }

    // ------------------------------------------------ notifications
    Column {
      id: notifPage
      visible: opacity > 0.01
      opacity: root.page === "notifications" ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 160 } }
      width: parent.width
      spacing: 6

      Header {
        title: "Notifications"
        hasSwitch: true
        switchOn: !root.s.dnd
        busyText: root.s.dnd ? "Silenced" : ""
        onSwitched: root.toggleDnd()
      }
      Label { visible: root.s.history.length === 0; text: "No notifications"; color: root.dim; topPadding: 10; bottomPadding: 10; width: root.innerWidth; horizontalAlignment: Text.AlignHCenter }
      Scroller {
        visible: root.s.history.length > 0
        height: Math.min(contentHeight, 380)
        contentHeight: notifList.implicitHeight
        Column {
          id: notifList
          width: parent.width
          spacing: 6
          Repeater {
            model: root.s.history
            delegate: Rectangle {
              id: card
              required property var modelData
              width: root.innerWidth
              height: Math.max(56, cardText.implicitHeight + 20)
              radius: 18
              color: cardMouse.containsMouse ? root.tileHover : root.tileOff
              MouseArea {
                id: cardMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.activateNotif(card.modelData)
              }
              Artwork {
                id: cardIcon
                x: 10
                y: 10
                width: 36
                height: 36
                radius: 10
                source: card.modelData.image
                fallbackGlyph: root.s.glyphs.bell
                glyphFont: root.s.iconFont
                glyphColor: card.modelData.urgent ? root.onColor("red") : root.fg
                fallbackColor: Qt.rgba(1, 1, 1, 0.1)
              }
              Column {
                id: cardText
                anchors.left: cardIcon.right
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.rightMargin: 36
                y: 10
                spacing: 1
                Label { width: parent.width; text: card.modelData.app + "  ·  " + root.s.timeAgo(card.modelData.time); font.pixelSize: 11; color: root.dim }
                Label { width: parent.width; text: card.modelData.title; font.weight: Font.DemiBold; color: card.modelData.urgent ? root.onColor("red") : root.fg }
                Label { width: parent.width; visible: text !== ""; text: card.modelData.body; font.pixelSize: 12; color: root.dim; wrapMode: Text.WordWrap; maximumLineCount: 2 }
              }
              Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 8
                y: 10
                width: 22
                height: 22
                radius: 11
                visible: cardMouse.containsMouse || closeMouse.containsMouse
                color: closeMouse.containsMouse ? root.tileHover : root.tileOff
                Glyph { anchors.centerIn: parent; text: "󰅖"; font.pixelSize: 11; color: root.dim }
                MouseArea { id: closeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.s.removeHistory(card.modelData.file) }
              }
            }
          }
        }
      }
      Rectangle {
        visible: root.s.history.length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        width: 120
        height: 30
        radius: 15
        color: clearMouse.containsMouse ? root.tileHover : root.tileOff
        Label { anchors.centerIn: parent; text: "Clear All"; font.pixelSize: 12; font.weight: Font.DemiBold }
        MouseArea { id: clearMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.s.clearHistory() }
      }
    }

    // ------------------------------------------------ calendar
    Column {
      id: calPage
      visible: opacity > 0.01
      opacity: root.page === "calendar" ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 160 } }
      width: parent.width
      spacing: 8

      property int offset: 0
      readonly property date shown: { var n = root.s.now; return new Date(n.getFullYear(), n.getMonth() + offset, 1) }
      readonly property var cells: {
        var first = shown
        var lead = (first.getDay() + 6) % 7
        var days = new Date(first.getFullYear(), first.getMonth() + 1, 0).getDate()
        var n = root.s.now
        var out = []
        for (var i = 0; i < 42; i++) {
          var d = new Date(first.getFullYear(), first.getMonth(), 1 - lead + i)
          out.push({ day: d.getDate(), inMonth: d.getMonth() === first.getMonth(),
            today: d.getFullYear() === n.getFullYear() && d.getMonth() === n.getMonth() && d.getDate() === n.getDate(),
            weekend: i % 7 >= 5 })
          if (i >= 34 && i % 7 === 6 && d.getMonth() !== first.getMonth()) break
        }
        return out
      }
      onVisibleChanged: if (!visible) offset = 0

      Item {
        width: root.innerWidth
        height: 34
        Rectangle {
          id: calBack
          width: 30; height: 30; radius: 15
          anchors.verticalCenter: parent.verticalCenter
          color: calBackMouse.containsMouse ? root.tileHover : root.tileOff
          Glyph { anchors.centerIn: parent; text: "󰅁"; font.pixelSize: 16 }
          MouseArea { id: calBackMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.back() }
        }
        Label {
          anchors.left: calBack.right
          anchors.leftMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          text: Qt.formatDate(calPage.shown, "MMMM yyyy")
          font.pixelSize: 16
          font.weight: Font.Bold
        }
        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: 6
          Round { width: 30; height: 30; glyph: "󰅁"; onClicked: calPage.offset-- }
          Round { width: 30; height: 30; glyph: "󰃭"; on: calPage.offset === 0; accent: root.onColor("red"); onClicked: calPage.offset = 0 }
          Round { width: 30; height: 30; glyph: "󰅂"; onClicked: calPage.offset++ }
        }
      }
      Grid {
        columns: 7
        columnSpacing: 0
        rowSpacing: 2
        Repeater {
          model: ["M", "T", "W", "T", "F", "S", "S"]
          delegate: Label { required property var modelData; width: root.innerWidth / 7; horizontalAlignment: Text.AlignHCenter; text: modelData; font.pixelSize: 11; font.weight: Font.DemiBold; color: root.dim }
        }
        Repeater {
          model: calPage.cells
          delegate: Item {
            required property var modelData
            width: root.innerWidth / 7
            height: 34
            Rectangle {
              anchors.centerIn: parent
              width: 30; height: 30; radius: 15
              visible: modelData.today
              color: root.onColor("red")
            }
            Label {
              anchors.centerIn: parent
              text: modelData.day
              font.pixelSize: 13
              font.weight: modelData.today ? Font.Bold : Font.Normal
              font.features: { "tnum": 1 }
              color: modelData.today ? "#ffffff" : !modelData.inMonth ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.25) : modelData.weekend ? root.dim : root.fg
            }
          }
        }
      }
    }

    // ------------------------------------------------ power
    Column {
      id: powerPage
      visible: opacity > 0.01
      opacity: root.page === "power" ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 160 } }
      width: parent.width
      spacing: 8

      Header { title: "Power" }
      Row {
        visible: root.powerProfiles.length > 0
        spacing: 6
        Repeater {
          model: root.powerProfiles
          delegate: Rectangle {
            required property var modelData
            readonly property bool sel: root.powerProfile === modelData
            width: (root.innerWidth - 6 * (root.powerProfiles.length - 1)) / Math.max(1, root.powerProfiles.length)
            height: 52
            radius: 16
            color: sel ? root.onColor(modelData === "power-saver" ? "yellow" : modelData === "performance" ? "orange" : "blue") : profMouse.containsMouse ? root.tileHover : root.tileOff
            Column {
              anchors.centerIn: parent
              spacing: 2
              Glyph { anchors.horizontalCenter: parent.horizontalCenter; text: root.profileGlyph(modelData); color: sel ? "#ffffff" : root.fg }
              Label { anchors.horizontalCenter: parent.horizontalCenter; text: root.profileLabel(modelData); font.pixelSize: 11; color: sel ? "#ffffff" : root.dim }
            }
            MouseArea {
              id: profMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: { root.powerProfile = modelData; root.run(["omarchy-powerprofiles-set", root.s.onBattery ? "battery" : "ac", modelData], true) }
            }
          }
        }
      }
      Grid {
        columns: 2
        spacing: 8
        Repeater {
          model: [
            ["󰌾", "Lock", ["omarchy-system-lock"], ""],
            ["󰒲", "Sleep", ["systemctl", "suspend"], ""],
            ["󰍃", "Log Out", ["omarchy-system-logout"], "confirm"],
            ["󰜉", "Restart", ["omarchy-system-reboot"], "confirm"],
            ["󰐥", "Shut Down", ["omarchy-system-shutdown"], "confirm"]
          ]
          delegate: Rectangle {
            id: pw
            required property var modelData
            readonly property bool armed: root.armedAction === modelData[1]
            width: (root.innerWidth - 8) / 2
            height: 44
            radius: 16
            color: armed ? root.onColor("red") : pwMouse.containsMouse ? root.tileHover : root.tileOff
            Behavior on color { ColorAnimation { duration: 140 } }
            Row {
              anchors.centerIn: parent
              spacing: 8
              Glyph { text: pw.modelData[0]; color: pw.armed ? "#ffffff" : root.fg }
              Label { text: pw.armed ? "Click again to " + pw.modelData[1].toLowerCase() : pw.modelData[1]; color: pw.armed ? "#ffffff" : root.fg; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea {
              id: pwMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                // Destructive actions ask for a second click, like a slide-to-confirm.
                if (pw.modelData[3] === "confirm" && !pw.armed) { root.armedAction = pw.modelData[1]; armTimer.restart(); return }
                root.armedAction = ""
                root.win.closeControls()
                root.run(pw.modelData[2], false)
              }
            }
          }
        }
      }
    }
  }

  property string armedAction: ""
  Timer { id: armTimer; interval: 3000; onTriggered: root.armedAction = "" }
}
