// Synced lyrics. Run: node tests/test-lyrics.mjs
import { readFileSync } from "node:fs"
import assert from "node:assert/strict"

const src = readFileSync(new URL("../IslandModel.js", import.meta.url), "utf8")
const { parseLrc, lyricAt } = new Function(src + "\nreturn { parseLrc, lyricAt }")()

const lines = parseLrc("[00:12.50] Second line\n[00:05.00] First line\r\n[01:02.3]  <3 you\n[00:20.00]\nnot a line\n[ar: Someone]")
assert.deepEqual(lines.map(l => l.t), [5, 12.5, 20, 62.3])
assert.equal(lyricAt(lines, 0), "", "before the first line")
assert.equal(lyricAt(lines, 5), "First line")
assert.equal(lyricAt(lines, 15), "Second line")
assert.equal(lyricAt(lines, 30), "", "instrumental gap")
assert.equal(lyricAt(lines, 99), "<3 you", "kept as plain text")
assert.deepEqual(parseLrc(null), [])
assert.equal(parseLrc("[00:01.00] " + "x".repeat(500))[0].text.length, 200, "clipped")
console.log("lyrics ok")
