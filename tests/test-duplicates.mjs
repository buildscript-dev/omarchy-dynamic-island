// One message, two ways in: the phone relays it and this machine's own copy of
// the app shows it too. Run: node tests/test-duplicates.mjs
import { readFileSync } from "node:fs"
import assert from "node:assert/strict"

const src = readFileSync(new URL("../IslandModel.js", import.meta.url), "utf8")
const Model = new Function(src + "\nreturn { sameMessage, seenRecently, rememberMessage }")()

const NOW = 1_700_000_000_000
const WINDOW = 12000

// KDE Connect wraps the phone's line in markup; phoned hands over the raw text.
assert.equal(Model.sameMessage("On my way &amp; almost there", "On my way & almost there"), true)
assert.equal(Model.sameMessage("WhatsApp<br/>On my way", "on my way"), false, "a stacked line is not the same message")
assert.equal(Model.sameMessage("", "On my way"), false, "an empty line matches nothing")
assert.equal(Model.sameMessage("Dinner at 8", "Dinner at 9"), false)

// Long messages are cut differently by each side; the first 60 characters decide.
const long = "Pick up the parcel from the locker before six please, code is 4417"
assert.equal(Model.sameMessage(long, long.slice(0, 60) + " …"), true)

let ring = []
ring = Model.rememberMessage(ring, "On my way", NOW, WINDOW)
assert.equal(Model.seenRecently(ring, "On my way &amp; almost", NOW + 900, WINDOW), false, "a short opening is not enough to call it the same")
assert.equal(Model.sameMessage("Hi", "Hi, are you there?"), false, "short messages must match in full")
assert.equal(Model.seenRecently(ring, "On my way", NOW + 900, WINDOW), true, "the second copy is a duplicate")
assert.equal(Model.seenRecently(ring, "On my way", NOW + WINDOW + 1, WINDOW), false, "the same text much later is a new message")
assert.equal(Model.seenRecently(ring, "Something else", NOW + 900, WINDOW), false)

// The ring forgets what has gone stale and never grows without bound.
let big = []
for (let i = 0; i < 40; i++) big = Model.rememberMessage(big, "message " + i, NOW + i, WINDOW)
assert.ok(big.length <= 8, "ring stays short")
assert.equal(Model.seenRecently(big, "message 39", NOW + 40, WINDOW), true)
const stale = Model.rememberMessage([{ body: "old", time: NOW }], "new", NOW + WINDOW + 1, WINDOW)
assert.deepEqual(stale.map(e => e.body), ["new"], "stale entries are dropped")

console.log("ok — message duplicates")
