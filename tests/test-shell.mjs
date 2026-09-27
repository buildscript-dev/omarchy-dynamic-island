// Outer shell outline. Run: node tests/test-shell.mjs
import { readFileSync } from "node:fs"
import assert from "node:assert/strict"

const src = readFileSync(new URL("../IslandModel.js", import.meta.url), "utf8")
const { shellPath } = new Function(src + "\nreturn { shellPath }")()
const nums = d => d.match(/-?\d+(\.\d+)?/g).map(Number)

// Tall card: fillets land on the straight sides, 8px out from the rim.
const card = shellPath(400, 200, 34, 5, 8, 20, false)
assert.ok(card.startsWith("M -13 20 A 8 8 0 0 1 -5 28"), card)
assert.ok(card.endsWith("413 20 Z"), card)

// Compact pill (30 tall, 6 below the top, 26px bar): the bar edge cuts the
// round ends, so the fillets meet the corner circles. Symmetric about w/2.
const pill = shellPath(136, 30, 15, 5, 8, 20, true)
const n = nums(pill)
assert.equal(n[0] + n[n.length - 2], 136, "left and right ends mirror")
assert.equal(n[1], 20); assert.equal(n[n.length - 1], 20)
assert.ok(!pill.endsWith("Z"), "open for the border stroke")
assert.ok(n.every(Number.isFinite))

// Nothing to draw when the island ends above the bar edge, or has no size.
assert.equal(shellPath(136, 10, 5, 5, 8, 26, false), "")
assert.equal(shellPath(0, 30, 15, 5, 8, 20, false), "")
console.log("shell ok")
