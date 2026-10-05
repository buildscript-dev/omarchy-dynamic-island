// The id of a BuildDots approval card as the island accepts it. Run: node tests/test-card.mjs
import { readFileSync } from "node:fs"
import assert from "node:assert/strict"

const src = readFileSync(new URL("../IslandModel.js", import.meta.url), "utf8")
const { cardId, G } = new Function(src + "\nreturn { cardId, G }")()

assert.equal(cardId("msg_c40561a20c074fad"), "msg_c40561a20c074fad")
assert.equal(cardId("a-b_C9"), "a-b_C9")
for (const bad of ["", "a b", "a/b", "../x", "a\"b", "-", "x".repeat(81), null, undefined, "id&choice=approve", "a\nb"])
  assert.equal(cardId(bad), bad === "-" ? "-" : "", `refuses ${JSON.stringify(bad)}`)
assert.ok(G.check && G.cross && G.check !== G.cross)
console.log("card ok")
