# Dynamic Island for Omarchy (`io.github.buildscript-dev.dynamic-island`)

An iPhone-style Dynamic Island that runs natively inside `omarchy-shell`
(Quickshell). A floating black bubble sits at the top of the screen and
springs open for whatever is happening: music, volume and brightness,
notifications, charging, Bluetooth, timers, screen recording. A built-in
Control Center covers Wi-Fi, Bluetooth, sound, brightness, tray and power.

Two shapes: `pill` (the default, a floating bubble) and `notch` (a MacBook
notch hanging from the top edge). It follows your Omarchy theme and bar
(height, colors, font scale), uses Hyprland blur for the translucent
styles, and tucks away over fullscreen windows.

## Install

```sh
omarchy plugin add https://github.com/buildscript-dev/omarchy-dynamic-island
```

Then add the widget to the bar's center in `~/.config/omarchy/shell.json`:

```json
{
  "bar": {
    "centerAnchor": true,
    "layout": { "center": [{ "id": "io.github.buildscript-dev.dynamic-island" }] }
  }
}
```

Restart the shell: `omarchy restart shell`.

Two optional steps:

- To let the island show volume, brightness and keyboard OSDs, add
  `"omarchy.osd"` to `disabledPlugins` (otherwise both appear). Set
  `"replaceOsd": false` on the island entry if you prefer the stock OSD.
- For blur on the `glass` and `bar` styles, add a layer rule in
  `~/.config/hypr/looknfeel.lua` (or your Hyprland config) for the layer
  namespace `omarchy-dynamic-island`.

Requires Omarchy with `omarchy-shell` (Quickshell). No other dependencies,
no root, no network access. It never edits your config for you.

## How it behaves

The island has five shapes. Moving between them is one spring animation:
it opens with a slight overshoot and closes with more damping. Content
fades out fast, then the new content comes in from a soft blur while the
shape is still settling. This is the same order Apple uses.

| Mode | Size | Triggered by |
|---|---|---|
| **Idle notch** | notch width × bar height, concave "ears" into the top edge | nothing happening |
| **Compact live activity** | widens sideways: leading + trailing content | music playing (art + waveform tinted by the album color), timer (orange countdown), screen recording (pulsing red dot + elapsed) |
| **Alert pill** | wide, a little taller | charging / on battery / low battery, Bluetooth connect/disconnect, Do Not Disturb, timer done, `omarchy osd -m` messages |
| **HUD** | drops down with a level bar | volume, brightness, keyboard backlight: every `omarchy osd -p` |
| **Notification peek** | medium card | new notifications from the Omarchy notification daemon |
| **Expanded** | large card | hover (rest ~0.3 s) or click |

**Expanded** shows **Now Playing**: artwork, title, artist and album, a
waveform, a seekable scrubber that thickens under the pointer, and
previous / play-pause / next. "Previous" restarts the track after 4 s, like
Apple does. When nothing is playing it shows a **home** view instead: a
large clock, this week's dates with today marked, 1/5/10/25-minute timer
pills (or the running timer with pause/cancel), a Focus (DND) toggle, and
"Stop recording" while you're recording. The top strip shows the player,
the battery, a DND moon and the mic-privacy dot.

Other details:

- The notch swells slightly under the pointer to show it can be clicked
  (a stand-in for haptics).
- Holding the volume key updates the HUD in place. A new HUD or alert
  replaces the current one straight away. Notifications queue behind it.
- Hovering an activity keeps it on screen until the pointer leaves.
- An orange dot shows while any app is recording from the microphone.

## Standalone (no top bar)

The island can replace the bar entirely. Hide the bar with
`omarchy toggle bar on` (that sets the `bar-off` flag; `omarchy toggle bar off`
brings it back). The island keeps working on its own:

- **Auto hide / auto appear**: with nothing live it slides away; music,
  timers, recording, phone mirroring, alerts, HUDs and notifications bring it
  back. Touch the top-center edge with the pointer to reveal it and the clock.
- **Monitor**: `monitor: "external"` (default) puts it on the external
  monitor, falling back to the built-in display when none is plugged in.
- **Size**: a 30 px floating bubble 6 px below the top edge (`islandHeight`,
  `pillInset`).
- **Workspaces**: switching flashes a pill with a dot per workspace.
- **Weather** sits under the date in the Control Center header.

## Layout: adaptive and symmetric

The island sizes itself to what it shows. A live activity has a leading and
a trailing view that hug the ends with the same inset, in equal-width slots,
and the clock sits exactly in the middle. The island stays centered on the
screen whatever is inside.

With two live activities at once (for example a timer while music plays),
the more important one owns the island and the other detaches into a small
round bubble beside it, like iOS's "minimal" presentation. The order is
recording, then phone mirroring, then timer, then music.

Other live alerts: buds connecting (with battery for each bud), noise mode
changes, keyboard layout switches, charging, Bluetooth, Focus.

## Control Center

Press **Super + A**, or right-click the island (or use the  button in the
expanded island), to open the Control Center. It holds everything that used
to sit on the right side of the bar. Click outside it or press Esc to close
(Esc on a sub-page goes back first).

- **Header**: time and date, the notification center (with a badge count),
  the calendar, and an **Update** button when Omarchy updates are available.

- **Wi-Fi**: the round icon toggles the radio. The tile opens the network list:
  click to join, type the password inline, click a saved network to disconnect,
  and use × to forget one.
- **Bluetooth**: toggle, your devices (connect/disconnect, battery, × forget)
  and nearby devices (click to pair). It searches while the page is open.
- **Phone** (Taildroid): mirror on/off, ADB devices (mirror, stop,
  disconnect), connect over Tailscale, Tailscale peers, and wireless-debugging
  pairing (address + code).
- **Notifications**: history with per-item dismiss, Clear All, and a silence switch.
- **Calendar**: month view with today marked; arrows to change month.
- Focus (Do Not Disturb) is the first quick button.
- **OnePlus Buds** (when OnePlus Experience is installed): per-bud and case
  battery, noise control, ANC strength, EQ and switches.
- **Sound**: volume slider (click the icon to mute) and the  button for
  output and input devices plus mic mute.
- **Brightness** slider (hidden on displays that can't be dimmed).
- Quick buttons: night light, stay awake, power mode, screenshot, screen
  recording, phone mirroring (Taildroid) and the power page (power mode, lock,
  sleep, log out, restart, shut down; destructive ones ask for a second click).
- **Tray** apps: left click activates, right click opens the app's menu.

It uses the same backends as Omarchy's own panels (Quickshell Networking,
Bluetooth, Pipewire and the `omarchy-*` helpers), so actions behave the same.

## Gestures

- **Hover** on the notch: opens after a short pause (`openOnHover`, `hoverDelay`).
- **Left click**: open or close. On a notification it runs the default
  action. On a HUD or alert it closes it and opens the island.
- **Right click** on a notification: dismisses it. Anywhere else: opens the Control Center.
- **Middle click**: play / pause.
- **Scroll** on the closed notch: volume ±2 %.
- Click the artwork in the expanded player to raise the player window.

## Styles and colors

Set these on the island's bar entry in `~/.config/omarchy/shell.json`.
Changes apply as soon as you save:

```json
{ "id": "io.github.buildscript-dev.dynamic-island", "style": "glass", "palette": "theme" }
```

| Key | Default | Meaning |
|---|---|---|
| `shape` | `pill` | `pill` = floating iPhone bubble inside the bar, sized to its content · `notch` = MacBook notch hanging from the top edge |
| `islandWidth` | `96` | idle width of the bubble in px (`pill`) |
| `pillInset` | `6` | gap between the bubble and the top edge (`pill`) |
| `islandHeight` | `30` | height of the bubble in px (`pill`) |
| `style` | `black` | `black` = true MacBook notch · `bar` = the bar's theme background/text · `glass` = translucent, blurred by Hyprland |
| `palette` | `apple` | `apple` = Apple system colors (green charging, orange timer, red record, indigo focus) · `theme` = your theme's accent/urgent |
| `notchWidth` | `200` | width of the idle notch in px (`notch`) |
| `openOnHover` / `hoverDelay` | `true` / `320` | open by resting the pointer on the notch |
| `showNotifications` | `true` | peek new notifications |
| `replaceOsd` | `true` | show `omarchy osd` (volume, brightness…) in the island |
| `hideInFullscreen` | `true` | slide away over fullscreen windows; a 3px strip at the top edge brings it back |
| `showWhenIdle` | `false` | keep the bare island visible when nothing is happening (off = auto-hide) |
| `artworkTint` | `true` | tint the waveform with the album's color |
| `showMicIndicator` | `true` | orange mic-in-use dot |
| `scrollVolume` | `true` | scroll on the notch for volume |
| `monitor` | `external` | `external` = the external monitor, falling back to the built-in display · `focused` = follows the focused monitor · `all` = one per monitor · or a connector name (`eDP-2`) |
| `showClock` / `clockFormat` | `true` / `HH:mm` | clock inside the island (Qt format string) |
| `showWorkspaces` | `true` | flash a workspace pill when switching |

## What it installs

Only the plugin folder. It declares:

1. A **service** that draws the island window on the `omarchy-dynamic-island`
   overlay layer.
2. A **bar-widget**: an invisible spacer in the bar's center that reserves
   the island's width, so bar widgets flow around it like the macOS menu bar.

It writes no files outside its own folder, installs no systemd units, and
never edits your configuration. Everything else is the two optional config
lines under [Install](#install), which you add yourself.

## Optional integrations

If these plugins are installed, the island loads their services and adds
their controls; if they are missing, nothing happens and those pages are
hidden.

| Plugin | Adds |
|---|---|
| [OnePlus Experience](https://github.com/buildscript-dev/omarchy-oneplus-experience) | earbuds page: battery, noise control, EQ · battery and noise-mode alerts |
| Taildroid | phone page: mirroring, calls, messages · call live activity |

## IPC

```sh
omarchy-shell island state               # JSON snapshot
omarchy-shell island expand | collapse
omarchy-shell island controls [main|wifi|bluetooth|audio|buds|phone|notifications|calendar|power]
omarchy-shell island phoneToggle         # Taildroid mirroring on/off
omarchy-shell island timer 300           # start a 5-minute timer
omarchy-shell island timerCancel
omarchy-shell island alert "<glyph>" "Title" "Value"
omarchy-shell island hud volume 40
omarchy-shell island notify "Title" "Body"
omarchy osd -i brightness -p 50          # the stock OSD command, now shown in the island
```

## Removal

```sh
omarchy plugin remove io.github.buildscript-dev.dynamic-island
```

Then take the island's entry out of `bar.layout.center` in
`~/.config/omarchy/shell.json`, remove `"omarchy.osd"` from `disabledPlugins`
to bring back the stock OSD, drop the `omarchy-dynamic-island` layer rule if
you added one, and `omarchy restart shell`.

Don't run this alongside another Dynamic Island plugin: they both register
the `island` IPC target.

## Keyboard shortcuts (optional, in ~/.config/hypr/bindings.lua)

| Keys | Opens |
|---|---|
| Super + A | Control Center |
| Super + Ctrl + W / B / A / P | Wi-Fi / Bluetooth / Sound / Power page |
| Super + Ctrl + Alt + D | Calendar |
| Super + Shift + Alt + , | Notifications |
| Super + Shift + I | Taildroid mirroring on/off |

Bind whichever you want; none are set up for you. The island can replace the
bar's right-side widgets entirely, since it hosts the clock, the Control
Center and the tray itself.

## License

MIT — see [LICENSE](LICENSE). Not affiliated with Apple. "Dynamic Island" is
used descriptively to name the interaction style.
