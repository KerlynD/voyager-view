# VoyagerView

A macOS menu bar app that shows the active layer of a ZSA Voyager keyboard. When the keyboard leaves
the base layer (hold, lock, toggle, one-shot), a semi-transparent picture of the keyboard with that
layer's keys fades in, centered on the screen with the mouse. When the keyboard returns to the base
layer, the picture fades out. The overlay never takes focus and clicks pass through it.

It talks to the keyboard directly over raw HID using ZSA's Oryx protocol. **Keymapp does not need to
be running.**

## Requirements

- macOS 14 or later (developed on macOS 27, Apple Silicon)
- Swift 6 toolchain. Command Line Tools are enough; Xcode is not needed.
- A Voyager running Oryx firmware (any layout compiled by Oryx includes the `oryx` module)

## Build and install

```sh
swift test                      # unit tests (protocol, labels, layout decoding, geometry, settings)
scripts/bundle.sh --install     # builds VoyagerView.app and copies it to ~/Applications
open ~/Applications/VoyagerView.app
```

`scripts/bundle.sh` without `--install` just leaves `VoyagerView.app` in the repo folder. Installing
to `~/Applications` is recommended, because **Launch at login** registers the app at its current
location.

To run from a terminal while developing:

```sh
swift run VoyagerView                 # menu bar app, logs to the terminal
swift run VoyagerView --demo          # start in demo mode
swift run VoyagerView --hid-probe 10  # no UI: pair, log every raw HID event for 10 s, exit
swift run VoyagerView --render 3 /tmp/nav.png   # draw layer 3 from the cached layout into a PNG
```

## Permissions

**None.** Opening the Voyager's vendor-defined raw HID interface (usage page `0xFF60`) doesn't need
Input Monitoring on macOS 27. This was checked on the real device: the app opens and pairs while the
Input Monitoring status is still "not determined", and no prompt appears. If a future macOS changes
this, the menu shows "Input Monitoring permission needed" with a button that opens the right pane in
System Settings.

## Using it

The menu bar icon (a keyboard) has these items:

| Item | What it does |
|------|--------------|
| status line | `Voyager connected · layer: Nav`, or `Voyager not found`, etc. |
| layout line | which Oryx layout is loaded and whether it's cached |
| Show test overlay | pins the overlay on screen (first non-base layer) until you turn it off |
| Demo mode | cycles through your layers on a timer, without the keyboard. It includes a 60 ms "tap" that must *not* show the overlay. |
| Window level test (demo) | like demo mode, but each time the overlay appears it uses a different window level and prints the level's name on the overlay. Use this inside a fullscreen game to see which levels make it on screen. |
| Settings… | live settings (below) |
| Reload layout | fetches the layout from Oryx again |

### Settings

Changes apply immediately and are saved to
`~/Library/Application Support/VoyagerView/config.json`. You can also edit that file by hand: the
app notices and reloads it. Bad or missing values fall back to their defaults one key at a time.

| Key | Default | Meaning |
|-----|---------|---------|
| `overallOpacity` | 0.92 | whole overlay, 0.1–1 |
| `backgroundOpacity` | 0.55 | the board behind the keys |
| `keyFillOpacity` | 0.65 | key caps |
| `labelOpacity` | 1.0 | text |
| `scale` | 1.0 | 0.4–1.5 of the default width (~860 pt) |
| `position` | `center` | `center`, `top`, `bottom`, `topLeft`, `topRight`, `bottomLeft`, `bottomRight` |
| `offsetX`, `offsetY` | 0 | points; positive Y moves up |
| `showDelayMs` | 120 | a layer must stay active this long before the overlay appears, so tapping Space/MO(1) doesn't flash it |
| `fadeDurationMs` | 100 | fade in/out |
| `autoHideSeconds` | 0 | hide after this long even if the layer is still active (0 = never). It comes back on the next layer change. |
| `baseLayer` | 0 | the layer that hides the overlay |
| `hiddenLayers` | `[]` | layers that never show the overlay (e.g. a gaming layer). Switching to one hides the overlay. |
| `showHoldLabels` | true | small hold-action label under the main label |
| `transparentKeys` | `dim` | `dim` shows what falls through from the base layer, dimmed; `blank` leaves the key empty |
| `highlightPressedKeys` | true | light up keys as you press them |
| `theme` | `dark` | `dark` or `light` |
| `accentMode` | `layerColor` | `layerColor` (from Oryx) or `custom` (`customAccentHex`) |
| `layoutHashId` | `dMyG6` | which Oryx layout to draw (see below) |
| `windowLevel` | `shielding` | `shielding`, `screenSaver`, `popUpMenu`, `statusBar`, `floating`, `custom` (`customWindowLevel`) |
| `logKeyEvents` | false | log every key press/release, not just layer changes |

### Changing the layout

The layout comes from the Oryx API using the **hash ID** in your layout's URL:
`https://configure.zsa.io/voyager/layouts/`**`dMyG6`**`/latest/0`. Put a different ID in Settings →
Layout (or `layoutHashId` in config.json) and press Apply. The app always fetches the `latest`
revision. The last good copy is cached in `~/Library/Application Support/VoyagerView/layout.json` and
used when you're offline. After editing your layout in Oryx, choose **Reload layout**.

### How keys are labeled

- A custom label from Oryx always wins. An Oryx emoji is used if there's no custom label.
- Otherwise the tap keycode is shown, with modifiers as glyphs in front (`⌘⇧4`).
- Hold actions appear as a small second line. Layer keys show the target layer's title (`Nav`).
- Hold-only keys show the hold action as the main label.
- Transparent keys show the base layer's key, dimmed. `KC_NO` and empty keys are blank.
- `QK_LLCK` is 🔒 and `CW_TOGG` is "Caps Word". The full table is in
  `Sources/VoyagerCore/Keymap/KeycodeLabels.swift`. A test checks that every code in the fixture is
  mapped. Unknown codes show their raw name without `KC_`.

### Lock badge

The firmware only reports *which* layer is active, not *why*. Because it also reports every key
press while paired, the app can tell when you press `QK_LLCK` on a layer. In that case it shows 🔒 next
to the layer title until you unlock or return to the base layer. Layers reached with TG/TO get no
badge (no reliable way to tell).

## How it works

- **Layer detection:** on connect the app sends `GET_PROTOCOL_VERSION` (`0xFE`) and `PAIRING_INIT`
  (`0x01`). The firmware answers `PAIRING_SUCCESS` and from then on pushes a `LAYER` event
  (`[0x05, layer, 0xFE]`) whenever the highest active layer changes. Nothing is polled.
- **No input lag:** raw HID is a separate USB interface and endpoint from the keyboard. Reports are
  read on a dedicated thread that only copies the bytes and hands them to the main thread. Writes go
  through their own queue. The device is opened non-exclusively, so Keymapp or Oryx in a browser
  still work alongside it.
- **Reconnects:** unplug/replug is handled by IOHIDManager's matching/removal callbacks and re-pairs
  automatically. After the Mac wakes, the app re-pairs.
- **Timing:** the show delay uses a strict dispatch timer. A plain timer in a windowless menu bar app
  is coalesced by macOS and fired up to ~100 ms late. Measured in demo mode on this machine: the
  overlay is on screen ~122 ms after the layer change with the default 120 ms delay, and drawing takes
  1–3 ms. Pairing to first `LAYER` event takes ~5 ms. Every show is logged with its timing.
- **Firmware caveat (DISCONNECT):** the app sends `DISCONNECT` (`0x03`) on quit, sleep and Ctrl-C. The
  current firmware (`oryx.c`) doesn't implement it: it replies `ERROR 0xFF` and stays paired (the same
  thing happens when Keymapp quits). This should be harmless: the macOS HID driver keeps reading the
  endpoint whether or not an app has it open, and if a send ever fails, the firmware sets
  `paired = false` and stops sending events after a single ≤100 ms timeout.

## The overlay window and fullscreen games

The overlay is an `NSPanel` (`borderless` + `nonactivatingPanel`, `ignoresMouseEvents`, never key or
main) with `canJoinAllSpaces`, `fullScreenAuxiliary`, `stationary` and `ignoresCycle`. Its default
level is `CGShieldingWindowLevel()`, the level above displays that a game has captured with
`CGDisplayCapture`.

**League of Legends fullscreen: verified (2026-11-16).** With the default `shielding` level, the
overlay shows over a real game in fullscreen and doesn't take focus. Layer holds and locks were tested
during play.

To check another game or a different level: Menu bar → **Window level test (demo)**, start the game,
and watch. Each time the overlay appears it uses the next level (`shielding`, `screenSaver`,
`popUpMenu`, `statusBar`, `floating`) and prints the level's name in the header. If nothing shows,
run the game in **borderless** mode.

## Logs

`~/Library/Logs/VoyagerView.log` (truncated at 2 MB), the unified log
(`log stream --predicate 'subsystem == "com.voyagerview.app"'`), and stderr when run from a terminal.
Every layer event is logged with the time since the previous one, and every overlay show with its
latency.

## Project layout

```
Package.swift
Sources/VoyagerCore/            pure logic, no I/O (unit-tested)
  Layers/OryxProtocol.swift       packet encode/decode
  Layers/LayerLockTracker.swift   🔒 inference
  Keymap/LayoutModels.swift       Oryx GraphQL models
  Keymap/KeycodeLabels.swift      keycode → label table
  Keymap/KeyLabeler.swift         label rules
  Geometry/VoyagerGeometry.swift  key positions + matrix map, from ZSA's keyboard.json
  Config/AppSettings.swift        settings model, lenient decoding
Sources/VoyagerView/            the app
  App/        main, AppDelegate (menu bar), SettingsWindow, logging/paths
  Layers/     LayerSource, OryxHIDLayerSource, DemoLayerSource
  Overlay/    OverlayPanel, OverlayController, KeyboardOverlayView, OverlaySnapshot
  Keymap/     LayoutStore (fetch + cache)
  Config/     ConfigStore (persist + hot reload)
Tests/VoyagerCoreTests/
Tests/Fixtures/oryx-layout-dMyG6.json
scripts/bundle.sh
```

## Build quirks on this machine

- **iCloud-synced Desktop:** iCloud adds Finder metadata to bundles, and then `codesign` fails with
  "resource fork, Finder information, or similar detritus not allowed". `.build` is a symlink to
  `~/Library/Caches/voyager-view-build`, and `bundle.sh` assembles the app there before copying it out.
  On a fresh clone outside iCloud you don't need either.
- **No SwiftUI macros with Command Line Tools:** `@State` and friends are macros in the macOS 27 SDK,
  and their plugin only ships with Xcode. The views use `ObservableObject` / `@Published` instead.
- **Swift Testing plugin path:** `Package.swift` passes the Testing macro plugin directory explicitly,
  because incremental test builds with Command Line Tools sometimes fail to find it otherwise.
