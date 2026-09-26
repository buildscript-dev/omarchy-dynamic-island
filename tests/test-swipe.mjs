// Swipe gestures on the island. Run: node tests/test-swipe.mjs
import { readFileSync } from "node:fs"
import assert from "node:assert/strict"

const src = readFileSync(new URL("../IslandModel.js", import.meta.url), "utf8")
const { swipeAction } = new Function(src + "\nreturn { swipeAction }")()

assert.equal(swipeAction(60, 4, "compact"), "tuck", "right")
assert.equal(swipeAction(-60, 4, "compact"), "tuck", "left")
assert.equal(swipeAction(20, 0, "compact"), "", "too short: a click")
assert.equal(swipeAction(60, 40, "compact"), "", "diagonal")
assert.equal(swipeAction(60, 0, "idle"), "", "nothing to tuck")
assert.equal(swipeAction(60, 0, "expanded"), "", "open views keep their own drags")
assert.equal(swipeAction(2, -50, "notification"), "dismiss", "up")
assert.equal(swipeAction(2, 50, "notification"), "", "down is not dismiss")
assert.equal(swipeAction(0, -50, "alert"), "dismiss")
assert.equal(swipeAction(0, -50, "compact"), "", "up on a live activity")
assert.equal(swipeAction(0, -50, "controls"), "")
console.log("swipe ok")
