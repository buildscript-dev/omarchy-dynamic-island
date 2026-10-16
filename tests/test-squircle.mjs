// Squircle outline. Run: node tests/test-squircle.mjs
import { readFileSync } from "node:fs"
import assert from "node:assert/strict"

const src = readFileSync(new URL("../IslandModel.js", import.meta.url), "utf8")
const { squirclePath } = new Function(src + "\nreturn { squirclePath }")()

// Walk the path's relative/absolute commands and return the end point of each
// segment, so the outline can be checked for closing and staying in bounds.
function points(d) {
  const t = d.trim().split(/\s+/)
  let i = 0, x = 0, y = 0, sx = 0, sy = 0
  const out = []
  const num = () => Number(t[i++])
  while (i < t.length) {
    const cmd = t[i++]
    if (cmd === "M") { x = sx = num(); y = sy = num() }
    else if (cmd === "L") { x = num(); y = num() }
    else if (cmd === "c") { i += 4; x += num(); y += num() }
    else if (cmd === "a") { i += 5; x += num(); y += num() }
    else if (cmd === "Z") { x = sx; y = sy }
    else throw new Error("unexpected " + cmd)
    out.push([x, y])
  }
  return out
}

for (const [w, h, r] of [[600, 200, 34], [136, 30, 15], [96, 30, 99], [0, 0, 10], [440, 560, 34]]) {
  const d = squirclePath(w, h, r, 0.6)
  assert.ok(!/NaN|Infinity/.test(d), `finite: ${d}`)
  const pts = points(d)
  // The last corner ends on the top edge (y = 0) left of the start, and Z
  // draws the straight top edge back to the first point.
  const [lx, ly] = pts[pts.length - 2]
  const [fx, fy] = pts[0]
  assert.ok(Math.abs(ly) < 0.05 && Math.abs(fy) < 0.05 && lx <= fx + 0.05, `closes ${w}x${h} r${r}: ${lx},${ly} -> ${fx},${fy}`)
  // Each corner meets its straight edge on the edge itself.
  assert.ok(pts.some(([x, y]) => Math.abs(x - w) < 0.05) && pts.some(([x, y]) => Math.abs(y - h) < 0.05), "touches right and bottom")
  for (const [x, y] of pts) assert.ok(x > -0.05 && y > -0.05 && x < w + 0.05 && y < h + 0.05, `in bounds ${w}x${h}: ${x},${y}`)
}
// A capsule (radius = half the height) has no room to smooth: plain arcs.
assert.match(squirclePath(136, 30, 15, 0.6), /^M 121 0 c 0 0 0 0 0 0 a 15 15/)
// With room, the corner starts 1.6 r from the edge (iOS smoothing 0.6).
assert.match(squirclePath(600, 200, 34, 0.6), /^M 545\.6 0 /)
console.log("squircle ok")
