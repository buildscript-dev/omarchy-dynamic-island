# Changelog

## 3.0.0

**Minimise to the island**
- Super + drag a window onto the island: a copy of it stays centred under the pointer,
  shrinks into the drop shape, and bends into the island with a mesh-shader genie
  (`Genie.qml`, `Ghost.qml`, `shaders/`). Tap the dock icon to bring the window back,
  tiled windows included. `island dockMinimize` does it for the focused window.
- The drop target swells to the size of the music card, springs, and names the window.

**Look and feel**
- Always solid black. Fixed the see-through island over bare wallpaper (an off-screen
  shadow layer) and the washed-out island when a special workspace was left showing.
- Apple's sizes (`appleSize`), the opening/closing springs and the content blur-in fitted
  to 30 fps iPhone footage, a gooey split when a second activity appears, an oval
  stopwatch bubble, rounded-square album art, one type scale (`Model.TYPE`).
- Inter ships with the plugin under its own family name ("Inter Island"), so it can no
  longer garble text next to a system Inter.
- Responsive: nothing is ever wider or taller than its screen.

**More of your system**
- New pills for Night Light, Stay Awake, Wi-Fi, Tailscale and USB; a soft tick for
  haptics; a notification sound; tap the playing track to focus its player without moving
  the cursor; touch and hold to open.
- Dismissing a phone notification dismisses it on the phone (KDE Connect).

**Removed**
- The Control Center (right-click page, `island controls` / `dial` / `messages`, the
  sound-output button, its `controlCenter` setting) and its 2,447 lines.
- The MacBook-notch shape, the outer shell band, the `bar` and `glass` styles, and all
  BuildDots-specific code. Old `shell.json` keys for them are ignored.
