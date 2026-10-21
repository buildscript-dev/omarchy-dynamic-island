// IslandModel's pure helpers in Qt's own JS engine, the one the island runs in. Run through tests/run.sh.
import QtQml
import "../IslandModel.js" as M
import "check.js" as C

QtObject {
  Component.onCompleted: {
    var xhr = new XMLHttpRequest()
    xhr.open("GET", Qt.resolvedUrl("cases.json"), false)
    xhr.send()
    var bad = C.check(M, JSON.parse(xhr.responseText))
    for (var i = 0; i < bad.length; i++) console.log("FAIL " + bad[i])
    console.log(bad.length ? "qt failed" : "qt ok")
    Qt.exit(bad.length ? 1 : 0)
  }
}
