import { readFileSync } from "node:fs"
const M = new Function(readFileSync(new URL("../IslandModel.js", import.meta.url), "utf8") + "\nreturn { tripFrom, currentTrip }")()
const eq = (a, b, m) => { if (JSON.stringify(a) !== JSON.stringify(b)) { console.error("FAIL " + m + " got " + JSON.stringify(a)); process.exit(1) } }
const n = (app, title, body, time) => ({ app, title, body: body || "", time: time || 1000 })
let r = M.tripFrom(n("Uber", "Your driver is arriving in 4 min", "WP 2418 Toyota"))
eq([r.type, r.stage, r.etaMin], ["ride", 2, 4], "uber eta")
r = M.tripFrom(n("Zomato", "Order confirmed", "Arriving in 25-30 mins"))
eq([r.type, r.stage, r.etaMin], ["food", 2, 25], "zomato range")
eq(M.tripFrom(n("Swiggy", "Delivered", "Enjoy your meal")).done, true, "done")
eq(M.tripFrom(n("Amazon", "Great Indian Festival deal for you!", "Save 10% extra")), null, "offer is not a trip")
eq(M.tripFrom(n("WhatsApp", "arriving in 5 min")), null, "other app")
eq(M.tripFrom(n("Amazon", "Out for delivery", "Arriving today by 7 PM")).stage, 2, "amazon out for delivery")
const h = [n("Uber", "Trip ended", "", 5000), n("Uber", "Driver arriving in 3 min", "", 4000), n("Zomato", "Preparing your order", "", 3000)]
eq(M.currentTrip(h, 6000, 1e6, 0).app, "Zomato", "closed uber skipped")
eq(M.currentTrip(h, 6000, 1e6, 3500), null, "hidden after")
eq(M.currentTrip(h, 9e6, 1000, 0), null, "too old")
console.log("trip ok")
