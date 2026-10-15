// The parsing in Service.qml hwLoad, run on a sample of nmcli + USB output.
import assert from "node:assert/strict"
function parse(t) {
  var parts = String(t).split("===USB\n"), wifi = "", tail = false
  var net = parts[0].split("\n")
  for (var i = 0; i < net.length; i++) {
    var f = net[i].split(/(?<!\\):/)
    if (f.length < 4) continue
    if (f[1] === "wifi" && f[2] === "connected") wifi = f[3].replace(/\\:/g, ":")
    if (f[0] === "tailscale0") tail = /^connected/.test(f[2])
  }
  var usb = (parts[1] || "").split("\n").map(function(x) { return x.trim() })
    .filter(function(x) { return x !== "" && !/host controller|root hub/i.test(x) })
  return { wifi, tail, usb }
}
const sample = "wlo1:wifi:connected:Cafe\\: Free WiFi\ntailscale0:tun:connected (externally):tailscale0\nlo:loopback:connected (externally):lo\nenp2s0:ethernet:unavailable:\n===USB\nxHCI Host Controller\nIntegrated Camera\nGalaxy S24\n"
const r = parse(sample)
assert.equal(r.wifi, "Cafe: Free WiFi", "escaped colon in an SSID")
assert.equal(r.tail, true)
assert.deepEqual(r.usb, ["Integrated Camera", "Galaxy S24"])
assert.equal(parse("wlo1:wifi:disconnected:\ntailscale0:tun:unavailable:\n===USB\n").wifi, "")
assert.equal(parse("tailscale0:tun:disconnected:\n===USB\n").tail, false)
console.log("hw ok")
