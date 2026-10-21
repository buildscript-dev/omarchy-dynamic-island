// Runs cases.json against IslandModel's helpers; returns the failures. Shared by test-otp.mjs (Node) and qt.qml (Qt).
function check(M, cases) {
  var bad = []
  for (var name in cases) {
    if (name === "_") continue
    for (var i = 0; i < cases[name].length; i++) {
      var got = JSON.stringify(M[name](cases[name][i][0])), want = JSON.stringify(cases[name][i][1])
      if (got !== want) bad.push(name + "(" + JSON.stringify(cases[name][i][0]).slice(0, 70) + ") = " + got + ", want " + want)
    }
  }
  return bad
}
