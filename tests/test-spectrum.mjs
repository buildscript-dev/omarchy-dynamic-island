// cava frames into waveform levels. Run: node tests/test-spectrum.mjs
import { readFileSync } from "node:fs"
import assert from "node:assert/strict"

const src = readFileSync(new URL("../IslandModel.js", import.meta.url), "utf8")
const { parseSpectrum } = new Function(src + "\nreturn { parseSpectrum }")()

assert.deepEqual(parseSpectrum("0;50;100;25;10;0;", 6), [0, 0.5, 1, 0.25, 0.1, 0])
assert.deepEqual(parseSpectrum("0;50;100;25;10;0", 6), [0, 0.5, 1, 0.25, 0.1, 0], "trailing ; optional")
assert.deepEqual(parseSpectrum("999;0;0;0;0;0;", 6)[0], 1, "clamped to 1")
assert.equal(parseSpectrum("1;2;3;", 6), null, "wrong bar count")
assert.equal(parseSpectrum("1;x;3;4;5;6;", 6), null, "not a number")
assert.equal(parseSpectrum("", 6), null)
console.log("spectrum ok")
