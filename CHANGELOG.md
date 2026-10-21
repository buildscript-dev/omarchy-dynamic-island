# Changelog

## 3.2.0

**One-time codes**
- A message holding a code (SMS, phone or desktop notification) shows as its own card: the code
  large and grouped, who sent it, how long it lasts, and a Copy button. The copy is the bare digits
  and stays out of clipboard history (`wl-copy --sensitive`). Old codes read "Code expired".
- The code is the standalone 4-8 digit run nearest "OTP" or "code"; card tails (XX1234), masked
  numbers, dates, amounts and the 1930 helpline never count.
- Android's blank "Sensitive notification content hidden" cards stay out of the way while the
  SMS sync brings the full message.

**Notifications**
- A click runs that notification's own action or opens its app. It no longer fires whichever
  popup is newest (a history click could open an unrelated crash report).
- One card per message across SMS, the KDE Connect relay and BuildDots.
- History split into "Needs a look" with Activity, and Notifications; black cards.

**Live activities**
- Trip (ride, food, delivery), flight (boarding, ETA) and sports (live score) cards from notifications.
- Phone battery pills for charging and low battery.

**Fixes**
- Qt's JS engine never matches a regex lookbehind, silently: the Wi-Fi and Tailscale pills had
  never fired. Gone everywhere; `tests/run.sh` now runs the helper tests in Node and in Qt.

## 3.1.0

- Removed the Control Center (2,447 lines): the island is now only the island.
- New 16:9 `preview.png`, a showcase video and GIF in `media/`, and a rewritten README.

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
