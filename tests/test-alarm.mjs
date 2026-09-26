// Alarm times. Run: node tests/test-alarm.mjs
import { readFileSync } from "node:fs"
import assert from "node:assert/strict"

const src = readFileSync(new URL("../IslandModel.js", import.meta.url), "utf8")
const { nextAlarm, clockText } = new Function(src + "\nreturn { nextAlarm, clockText }")()

const now = new Date(2026, 8, 26, 15, 0, 0).getTime()
assert.equal(clockText(nextAlarm("16:30", now)), "16:30")
assert.equal(nextAlarm("16:30", now) - now, 90 * 60 * 1000, "later today")
assert.equal(nextAlarm("7:05", now) - now, (16 * 60 + 5) * 60 * 1000, "tomorrow morning")
assert.equal(nextAlarm("15:00", now) - now, 24 * 3600 * 1000, "the current minute means tomorrow")
for (const bad of ["24:00", "12:60", "noon", "", "1:2", "12:30; rm -rf"]) assert.equal(nextAlarm(bad, now), 0, bad)
console.log("alarm ok")
