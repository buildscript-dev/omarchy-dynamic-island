.pragma library
// One engine-wide slot for the running island Service. A `.pragma library`
// file is shared by every QML file that imports it, so the bar widget can
// find the live service even when a replacement bar hands it a shell scoped
// to the bar (which can't see other plugins' services).
var current = null
