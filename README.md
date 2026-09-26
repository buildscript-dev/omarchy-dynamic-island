# Dynamic Island for Omarchy (`io.github.buildscript-dev.dynamic-island`)

![The island going from its idle pill to a volume HUD, a charging alert and the expanded card](demo.gif)

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
  While `replaceOsd` is on the island answers the `osd` IPC target itself,
  so `omarchy osd` lands in the island; with it off the island answers on
  `dynamic-island-osd` instead and the stock OSD keeps its own target.
- For blur on the `glass` and `bar` styles, add a layer rule in
  `~/.config/hypr/looknfeel.lua` (or your Hyprland config) for the layer
  namespace `omarchy-dynamic-island`.

Requires Omarchy with `omarchy-shell` (Quickshell). No other dependencies,
no root, no installer, no background daemon. It never edits your config for
you. It downloads album artwork for streaming players unless you turn that
off — see [Network use](#network-use).

## How it behaves

The island has six modes. Moving between them is one spring animation:
it opens with a slight overshoot and closes with more damping. Content
fades out fast, then the new content comes in from a soft blur while the
shape is still settling. This is the same order Apple uses.

| Mode | Size | Triggered by |
|---|---|---|
| **Idle** | a small bubble (`pill`), or a notch with concave "ears" into the top edge (`notch`) | nothing happening |
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
brings it back), and set `"showWhenIdle": false` on the island entry. It
then keeps working on its own:

- **Auto hide / auto appear**: with nothing live it slides away; music,
  timers, recording, phone mirroring, alerts, HUDs and notifications bring it
  back. Touch the top-center edge with the pointer to reveal it and the clock.
- **Monitor**: `"monitor": "external"` pins it to the external monitor,
  falling back to the built-in display when none is plugged in. The default,
  `focused`, follows the monitor you are working on instead.
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

Right-click the island, or use the  button in the expanded island, to open
the Control Center — or bind a key to it, see
[Keyboard shortcuts](#keyboard-shortcuts-optional-in-confighyprbindingslua).
It holds everything that usually sits on the right side of the bar. Click
outside it or press Esc to close (Esc on a sub-page goes back first).

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
  output and input devices plus mic mute, and a volume slider for each app
  playing sound (click its icon to mute just that app).
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

## Settings

Every setting goes on the island's entry in `~/.config/omarchy/shell.json`.
Changes apply as soon as you save the file — no restart:

```json
{ "id": "io.github.buildscript-dev.dynamic-island", "style": "glass", "palette": "theme" }
```

| Setting | Default | What it does |
|---|---|---|
| `shape` | `pill` | `pill` = a floating bubble at the top of the screen · `notch` = a MacBook-style notch attached to the top edge |
| `style` | `black` | `black` = solid black, like a real notch · `bar` = your bar's color · `glass` = see-through and blurred |
| `palette` | `apple` | `apple` = Apple's colors (green charging, orange timer, red recording) · `theme` = your Omarchy theme's colors |
| `showWhenIdle` | `true` | keep the island on screen with nothing happening. Turn it **off** for the standalone look: it hides itself and comes back for music, alerts and notifications, or when you touch the top edge |
| `monitor` | `focused` | `focused` = follows the monitor you are working on · `external` = the external monitor, or the built-in one when nothing is plugged in · `all` = one per monitor · or a connector name such as `HDMI-A-1` |
| `onlineExtras` | `true` | let the island use the internet: album artwork for streaming players, synced lyrics, the weather line, the Omarchy update check. Off = no network requests at all |
| `showNotifications` | `true` | show new notifications in the island |
| `muteWhileMirrored` | `true` | with the phone's screen mirrored on this desktop, leave its notifications, messages and status to the mirror. Calls still come through. Needs Taildroid |
| `replaceOsd` | `true` | show volume and brightness in the island instead of Omarchy's pop-up |
| `hideInFullscreen` | `true` | get out of the way of fullscreen windows; a 3 px strip at the top edge brings it back |
| `openOnHover` / `hoverDelay` | `true` / `320` | open by resting the pointer on it, after this many ms |
| `scrollVolume` | `true` | scroll on the island to change volume |
| `showClock` / `clockFormat` | `true` / `HH:mm` | clock inside the island (Qt format: `HH:mm`, or `h:mm AP` for AM/PM) |
| `showWorkspaces` | `true` | flash the workspace when you switch |
| `artworkTint` | `true` | color the music view from the album art |
| `showMicIndicator` | `true` | orange dot while the microphone is in use |
| `islandWidth` / `islandHeight` / `pillInset` | `96` / `30` / `6` | size of the bubble and its gap from the top edge (`pill`) |
| `notchWidth` | `200` | width of the notch (`notch` shape only) |

Omarchy's settings UI reads the same list, so you can also change these from
the plugin's settings panel instead of editing JSON.

## Network use

The island itself makes two kinds of request. The first is downloading album
artwork for players that publish it as an `http(s)` URL (Spotify and other
streaming clients). Because that URL comes from the player, the download is
held to fixed limits:

- plain HTTP and HTTPS only, including every redirect (at most 3);
- at most 4 MB, enforced by the kernel as a file-size limit while the file is
  written, so a response that never ends or lies about its length stops at
  4 MB and is thrown away;
- 10 seconds for the transfer, 15 for the whole job;
- no `~/.curlrc` and no proxy or TLS settings from the environment.

The one image kept is the current track's, in
`/run/user/<uid>/omarchy-dynamic-island` (per-user, mode 0700, in memory,
gone at logout). The island draws and tints only that copy, never the URL.

The second is looking up synced lyrics for the playing track at
[lrclib.net](https://lrclib.net): one HTTPS `GET` per track, which sends the
track's artist, title and length to lrclib.net. The answer is capped at
256 KB and 12 seconds, and only the line being sung is drawn, as plain text.

It also runs Omarchy's own `omarchy-weather-status` and
`omarchy-update-available` helpers, which reach the network themselves.

Set `"onlineExtras": false` and all of these stop. Nothing else in the plugin
opens a connection, and nothing besides the lyrics lookup above is sent
anywhere.

## What it runs

The island lives inside the long-running Omarchy shell, so every program it
starts follows the same rules (`IslandModel.js`, `SafeProcess.qml`):

- **Fixed executables.** Each command is an absolute path in a root-owned
  directory: `/usr/share/omarchy/bin` for Omarchy's helpers, `/usr/bin` for
  the rest. Nothing is looked up on your `PATH`.
- **Closed environment.** Children get a short allowlist of session
  variables (Wayland, Hyprland, D-Bus, XDG base and picture/video folders)
  and a fixed `PATH=/usr/share/omarchy/bin:/usr/bin`. Nothing that names a
  program to run, such as `EDITOR` or `BROWSER`, is passed on.
- **Deadlines.** Every command runs under GNU `timeout`, which signals its
  whole process group and follows up with `KILL`. The only exceptions are
  the things you start on purpose that are meant to keep running: a screen
  recording, a screenshot selection, the update terminal, the lock screen and
  log-out/restart/shut-down, and a phone attachment you open.
- **Capped output.** Anything the island reads back is capped while it is
  produced (`head -c`, with `pipefail`) and dropped if it runs over. That
  covers helper output, the notification files, `shell.json` and the
  notification history.
- **Regular files only.** Files are read only if they are regular files and
  not symlinks, and a path swapped for a FIFO afterwards just runs into the
  deadline. The `FileView`s only watch for changes; they never load a file.

Everything drawn from outside (notification text, media titles, device
names, messages, IPC arguments) is rendered as plain text
(`Text.PlainText`) and shortened first. Images load only from local files
and the shell's own icon providers. Notification pictures load only from
Omarchy's own copies in `~/.local/state/omarchy/notifications/images`.

## What it installs

Only the plugin folder. It declares:

1. A **service** that draws the island window on the `omarchy-dynamic-island`
   overlay layer.
2. A **bar-widget**: an invisible spacer in the bar's center that reserves
   the island's width, so bar widgets flow around it like the macOS menu bar.

It installs no systemd units and never edits your configuration. The only
file it writes is the current album-art image in
`/run/user/<uid>/omarchy-dynamic-island` (see [Network use](#network-use)).
Removing an entry from the Control Center's notification list deletes that
entry from Omarchy's own history folder, as Omarchy's panel does. Everything else is the two optional config
lines under [Install](#install), which you add yourself.

## Optional integrations

If these plugins are installed, the island loads their services and adds
their controls; if they are missing, nothing happens and those pages are
hidden. The island loads a plugin's `Service.qml` from
`~/.config/omarchy/plugins/<id>/` only when that file is a regular file, the
same code Omarchy loads for that plugin. It is never downloaded.

| Plugin | Adds |
|---|---|
| [OnePlus Experience](https://github.com/buildscript-dev/omarchy-oneplus-experience) | earbuds page: battery, noise control, EQ · battery and noise-mode alerts |
| [Taildroid](https://github.com/buildscript-dev/omarchy-taildroid) (`io.github.buildscript-dev.taildroid`) | phone page: mirroring, calls, messages · call live activity · quiet island while the phone is mirrored |

If the [`cava`](https://github.com/karlstav/cava) package is installed, the
music waveform follows the real audio while something plays. Without it the
bars keep their made-up dance.

The phone page needs my Taildroid fork, which adds calls and messages to
[raythurman2386/taildroid](https://github.com/raythurman2386/taildroid).
Install it the same way, or leave it out: without it the page stays hidden,
the phone IPC methods answer `no-taildroid`, and nothing else changes.

### With the phone on screen

While the phone's screen is mirrored on this desktop, the mirror is already
showing everything the phone has to say, so the island stops repeating it:
notifications relayed from the phone, incoming messages, and "connected",
"nearby" and "hotspot" alerts all stay quiet until the mirror closes. An
incoming call still takes over the island, and the island itself gets out of
the way: no mirror live activity counting how long the phone has been up,
because the mirror window is already the indicator. Set `muteWhileMirrored` to
`false` to get all of it back.

This counts any mirror window — Taildroid's own, a DeX display, a single
mirrored app, or a plain `scrcpy` — however it was started.

A message that reaches this machine twice, once relayed from the phone and
once from this desktop's own copy of the same chat app, shows once: the first
one in wins, and a repeat of the same text within twelve seconds is dropped.

## IPC

Any program in your session can call these, so they only change what the
island shows. None of them places a call, sends a message or reads one out.
`state` reports what kind of thing is showing, never its text. Arguments are
checked and shortened, and a page name that isn't on the list is refused.

```sh
omarchy-shell island state               # JSON snapshot (kinds, not contents)
omarchy-shell island ping
omarchy-shell island expand | collapse
omarchy-shell island controls [main|wifi|bluetooth|audio|buds|phone|messages|call|thread|notifications|calendar|power]
omarchy-shell island timer 300           # start a 5-minute timer
omarchy-shell island timerCancel
omarchy-shell island stopwatch           # start / pause the stopwatch
omarchy-shell island stopwatchReset
omarchy-shell island alarm 7:30          # next time the clock reads 7:30 (24-hour); kept until the shell restarts
omarchy-shell island alarmCancel
omarchy-shell island alert "<glyph>" "Title" "Value"
omarchy-shell island hud volume 40
omarchy-shell island notify "Title" "Body"
omarchy osd -i brightness -p 50          # the stock OSD command, now shown in the island

# Phone continuity. Every one of these needs the Taildroid fork below;
# without it they change nothing and answer "no-taildroid".
omarchy-shell island phoneToggle         # mirroring on/off
omarchy-shell island messages            # open the Messages page
omarchy-shell island answer              # pick up the call ringing on screen right now
omarchy-shell island hangup              # end the current call
omarchy-shell island dial "+15551234"    # open the keypad with this number; you press call
omarchy-shell island phoneDex            # open the phone's desktop mode
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
