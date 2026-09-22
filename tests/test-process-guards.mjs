// The rules every child process and every image source is held to.
// Run: node tests/test-process-guards.mjs
import { readFileSync } from "node:fs"
import { execFileSync } from "node:child_process"
import assert from "node:assert/strict"

const src = readFileSync(new URL("../IslandModel.js", import.meta.url), "utf8")
const Model = new Function(src + "\nreturn { exe, childEnv, bounded, direct, utf8Length, capped, clip, localImage }")()

// Executables are absolute and live in root-owned directories.
assert.equal(Model.exe("omarchy-shell"), "/usr/share/omarchy/bin/omarchy-shell")
assert.equal(Model.exe("wl-paste"), "/usr/bin/wl-paste")
assert.equal(Model.exe("/usr/bin/systemctl"), "/usr/bin/systemctl")
assert.deepEqual(Model.direct(["xdg-open", "/tmp/a b"]), ["/usr/bin/xdg-open", "/tmp/a b"])

// The environment is an allowlist with a fixed PATH; nothing that names a program.
const fake = { HOME: "/home/u", PATH: "/home/u/evil", EDITOR: "evil", BROWSER: "evil", WAYLAND_DISPLAY: "wayland-1", LANG: "a\nb" }
const env = Model.childEnv(k => fake[k])
assert.equal(env.PATH, "/usr/share/omarchy/bin:/usr/bin")
assert.equal(env.HOME, "/home/u")
assert.equal(env.WAYLAND_DISPLAY, "wayland-1")
assert.equal(env.EDITOR, undefined)
assert.equal(env.BROWSER, undefined)
assert.equal(env.LANG, undefined, "a value with control characters is dropped")

// A bounded command runs under timeout, keeps argv intact, and caps its output.
const cmd = Model.bounded(["printf", "%s", "a'b; $(x)"], 5, 3)
assert.equal(cmd[0], "/usr/bin/timeout")
assert.equal(execFileSync(cmd[0], cmd.slice(1)).toString(), "a'b;", "argv is never re-parsed by a shell; output stops at cap + 1")
assert.equal(Model.capped("a'b;", 3), null, "one byte over the cap is refused")
assert.equal(Model.capped("abc", 3), "abc")
const quiet = Model.bounded(["printf", "noise"], 5, 0)
assert.equal(execFileSync(quiet[0], quiet.slice(1)).toString(), "", "fire-and-forget output goes nowhere")
let code = 0
try { execFileSync(...(c => [c[0], c.slice(1)])(Model.bounded(["sleep", "10"], 1, 0))) } catch (e) { code = e.status }
assert.equal(code, 124, "the deadline ends a command that runs too long")

// UTF-8 size never undercounts, so a multibyte overflow is still caught.
assert.equal(Model.utf8Length("aé€😀"), 1 + 2 + 3 + 4)
assert.equal(Model.capped("€€", 5), null)

// External strings are shortened and lose control characters.
assert.equal(Model.clip("x".repeat(10), 5), "xxxx…")
assert.equal(Model.clip("a\u0000b\u001bc", 10), "abc")

// Only local files and the shell's own image providers load.
assert.equal(Model.localImage("https://example.com/a.png"), "")
assert.equal(Model.localImage("http://127.0.0.1/a.png"), "")
assert.equal(Model.localImage("data:image/png;base64,AAAA"), "")
assert.equal(Model.localImage("qrc:/x.png"), "")
assert.equal(Model.localImage("/dev/zero"), "")
assert.equal(Model.localImage("file:///proc/self/environ"), "")
assert.equal(Model.localImage("/tmp/../etc/x.png"), "")
assert.equal(Model.localImage("relative.png"), "")
assert.equal(Model.localImage("/tmp/art.png"), "file:///tmp/art.png")
assert.equal(Model.localImage("file:///tmp/art.png"), "file:///tmp/art.png")
assert.equal(Model.localImage("image://icon/firefox"), "image://icon/firefox")

console.log("process and image guards: ok")
