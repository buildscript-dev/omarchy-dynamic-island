// IslandModel's pure helpers in Node. Prefer tests/run.sh: it runs the same cases in Qt's engine too.
import { readFileSync } from "node:fs"

const read = (f) => readFileSync(new URL(f, import.meta.url), "utf8")
const M = new Function(read("../IslandModel.js") + "\nreturn { otpCode, otpMinutes, otpGroup, execArgvOf, isRedacted, nmcliFields }")()
const check = new Function(read("check.js") + "\nreturn check")()
const bad = check(M, JSON.parse(read("cases.json")))
for (const b of bad) console.error("FAIL " + b)
if (bad.length) process.exit(1)
console.log("node ok")
