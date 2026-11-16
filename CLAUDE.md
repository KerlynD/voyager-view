# voyager-view

A macOS overlay that shows what's on the active layer of my ZSA Voyager keyboard. When the keyboard leaves the base layer (by holding a layer key, locking a layer, toggling one, anything), a semi-transparent picture of the keyboard appears **centered on the screen I'm using**, on top of everything, including **League of Legends in fullscreen**. It shows the keys for that layer. When I go back to the base layer, it disappears.

## Why

I can see the base layer by looking at my keycaps. On the other layers I forget what each key does. I want a quick visual reminder that appears only while I'm on a non-base layer.

## Hard constraints

1. **No added input lag.** The app must never slow down typing or gaming. It only listens for events (see "Layer detection" for why this is safe) and must never block the keyboard.
2. **Keymapp must not be required.** The app talks to the keyboard directly over raw HID. I don't want Keymapp running all the time.
3. **It must show over League of Legends in fullscreen mode.** This is the main use case and the biggest risk. See "The overlay window".
4. **It must never steal focus or block clicks.** Taking focus mid-game is unacceptable.

## Environment (verified on this machine)

- macOS 27 on Apple Silicon (arm64)
- Swift 6.4 with **Command Line Tools only (no Xcode.app)**. Everything must build with `swift build` / `swift test`, not an `.xcodeproj`.
- League of Legends and the Riot Client are installed. I play LoL in **fullscreen**.
- Keymapp.app is installed but I don't want to depend on it.
- The Voyager is connected. `hidutil list` shows:
  - Vendor ID `0x3297`, Product ID `0x1977`, product name "Voyager"
  - Raw HID interface: **usage page `0xFF60` (65376), usage `0x61` (97)**. That's the one to open. The others are the normal keyboard, mouse, and consumer interfaces, so don't touch them.

## Tech decisions

- **Language/UI:** Swift. AppKit for windowing; SwiftUI hosted inside the panel is fine for drawing the keyboard.
- **HID:** IOKit's `IOHIDManager`, matching on VID/PID **and** usage page/usage. Open it with `kIOHIDOptionsTypeNone` (non-exclusive), so Keymapp or Oryx can still connect if I open them.
- **Packaging:** a SwiftPM executable target plus `scripts/bundle.sh`, which wraps the binary into `VoyagerView.app` with an `Info.plist` (`LSUIElement = true`, so there's no Dock icon). Also call `NSApp.setActivationPolicy(.accessory)` in code so `swift run` behaves the same way.
- **App shape:** a menu bar app (`NSStatusItem`). The menu shows the connection status ("Voyager connected · layer: Nav") and has Show test overlay, Demo mode, Settings…, Reload layout, Quit.

## Layer detection: Oryx raw HID protocol (verified from source)

My keyboard runs Oryx firmware, which includes ZSA's `oryx` QMK module. The source is in https://github.com/zsa/qmk_modules, in `oryx/oryx.h` and `oryx/oryx.c`. Re-read both before implementing. What matters:

- Packets are **32 bytes** (`RAW_EPSIZE`). Byte 0 is the command or event code, then the params. `ORYX_STOP_BIT` is `-2` (`0xFE` as a byte) and marks the end of the meaningful payload.
- Host → keyboard commands (enum `Oryx_Command_Code`): `0x00` GET_FW_VERSION, `0x01` PAIRING_INIT, `0x02` PAIRING_VALIDATE, `0x03` DISCONNECT, `0x04` SET_LAYER, …, `0xFE` GET_PROTOCOL_VERSION.
- Keyboard → host events (enum `Oryx_Event_Code`): `0x00` GET_FW_VERSION, `0x01` PAIRING_INPUT, `0x02` PAIRING_KEY_INPUT, `0x03` PAIRING_FAILED, `0x04` PAIRING_SUCCESS, **`0x05` LAYER `[0x05, layer, 0xFE]`**, `0x06` KEYDOWN `[0x06, col, row, 0xFE]`, `0x07` KEYUP, …, `0xFE` PROTOCOL_VERSION, `0xFF` ERROR `[0xFF, code]`.
- **Pairing:** send `0x01` (PAIRING_INIT). The current firmware pairs immediately: it replies `PAIRING_SUCCESS` and then sends a `LAYER` event with the current layer. No key-sequence challenge is needed in protocol v5. Send `0xFE` first and log the protocol version; if it isn't 5, log a warning.
- After pairing, the firmware **pushes** a `LAYER` event whenever the highest active layer changes. That covers MO, LT, TG, TO, OSL, layer lock (`QK_LLCK`), and default-layer changes, because it reports `get_highest_layer(layer_state | default_layer_state)` and skips duplicates. **No polling.**
- While paired it also sends KEYDOWN and KEYUP events with matrix col/row for every key. Ignore them, or use them for the optional key highlighting below.
- On quit or sleep, send `0x03` (DISCONNECT) so the firmware stops sending events.
- Host → keyboard writes are 32-byte output reports. On macOS, check whether `IOHIDDeviceSetReport` needs a leading report-ID byte. QMK raw HID has no report ID, so try sending exactly 32 bytes with report ID 0 first.

### Why this doesn't add lag, and what could break that

- Raw HID is a separate USB interface and endpoint from the keyboard endpoint. Keystrokes don't wait on it.
- **Firmware caveat:** `raw_hid_send_oryx` calls `send_report`. If the host stops reading the raw HID endpoint, sends can fail or time out, and the firmware then sets `paired = false`. To avoid any chance of stalls:
  - Read input reports continuously on a dedicated thread with its own run loop (`IOHIDDeviceRegisterInputReportCallback`). **Never do UI work or anything slow in the callback.** Copy the bytes, hand them to the main queue, and return.
  - If the app is about to stop reading (quit, sleep, crash handler where possible), send DISCONNECT first.
- Handle plug and unplug (matching and removal callbacks on `IOHIDManager`) and re-pair automatically. Also re-pair after the Mac wakes (`NSWorkspace.didWakeNotification`), because the firmware may have dropped pairing.
- Find out whether macOS 27 asks for **Input Monitoring** permission to open a vendor-defined (`0xFF60`) HID interface. It usually doesn't for vendor pages. If it does, detect that, show a clear prompt, and document it in the README.

### Abstraction

Define a `LayerSource` protocol (`AsyncStream<Int>` or a callback) with three implementations:
- `OryxHIDLayerSource`: the real one.
- `DemoLayerSource`: cycles through the layers on a timer, for testing without the keyboard.
- `KeymappLayerSource`: **optional, low priority.** It polls the Keymapp gRPC `GetStatus` over its Unix socket. Only build it if there's time left; it's not part of the default path.

## The overlay window

- `NSPanel` with `[.borderless, .nonactivatingPanel]`, `ignoresMouseEvents = true`, `isOpaque = false`, clear background, `hasShadow = false`, `hidesOnDeactivate = false`, `canBecomeKey` / `canBecomeMain` → false.
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`.
- **Window level, the LoL fullscreen problem:** macOS games in "fullscreen" either run as a native fullscreen Space (covered by `.fullScreenAuxiliary` plus a high level) or **capture the display** (`CGDisplayCapture`), where only windows at or above `CGShieldingWindowLevel()` show. Default to **`CGShieldingWindowLevel()`** and make the level a hidden or advanced setting, so other levels like `.screenSaver` can be tried.
- **Test it over LoL fullscreen early**, before polishing anything else. Build the bare panel and a demo source first, then ask me to launch a practice game. If fullscreen can't be overlaid after trying both levels, tell me plainly and write it in the README (fallback: play LoL in borderless). Don't fake success.
- Keep the panel cheap: no continuous animation, redraw only when the layer or settings change. It must not hurt the game's FPS.
- **Position:** **centered** on the screen that has the mouse cursor (`NSEvent.mouseLocation` matched against `NSScreen.screens`). Re-check the screen each time the overlay appears. Center is the default; other positions are optional settings.

## The keymap (what to draw)

### Source: the Oryx GraphQL API (verified working)

- My layout: https://configure.zsa.io/voyager/layouts/dMyG6/latest/0 (hash ID **`dMyG6`**, title "angel 3 layer").
- The endpoint `POST https://oryx.zsa.io/graphql` works without auth. A real response is saved at `Tests/Fixtures/oryx-layout-dMyG6.json`, so use it for tests and as a reference for the schema. The query that produced it:
```json
{"operationName":"getLayout",
 "variables":{"hashId":"dMyG6","revisionId":"latest","geometry":"voyager"},
 "query":"query getLayout($hashId: String!, $revisionId: String!, $geometry: String) { layout(hashId: $hashId, geometry: $geometry, revisionId: $revisionId) { title geometry revision { hashId title qmkVersion layers { title position color keys } } } }"}
```
- Fetch it at launch, cache the last good copy in `~/Library/Application Support/VoyagerView/layout.json`, fall back to the cache when offline, and add a "Reload layout" menu item. The layout hash ID is a setting (default `dMyG6`).

### My layers (from the fixture)

| # | Title | Color |
|---|-------|-------|
| 0 | Main | `#fff4d4` |
| 1 | Symbols | `#FFE3B8` |
| 2 | Medi/Sys | `#E3A23B` |
| 3 | Nav | `#2E4A9E` |

Layer access, all on thumb keys: hold left thumb inner (idx 24, tap Space) → Symbols; hold left thumb outer (idx 25) → Nav; hold right thumb outer (idx 51, tap Backspace) → Medi/Sys. Every non-base layer has `QK_LLCK` (layer lock) at idx 0, so **locked layers are common and must work.** The overlay stays visible for as long as the layer is locked.

### Key JSON shape

Each layer has exactly 52 `keys`. Each key looks like `{tap, hold, doubleTap, tapHold, customLabel, icon, emoji, glowColor, ...}`. Each action is `{code, layer, modifier, modifiers, macro, description, color}` or `null`.

Label rules:
1. `customLabel` always wins. My layout uses lots of them, e.g. "copy", "paste", "new tab", "claude", "wispr flow".
2. Otherwise use the tap action's `code` through the keycode → label table, with `modifiers` shown as glyphs (`⌘⌥⌃⇧`) in front, e.g. LGUI+LSHIFT+KC_4 → `⌘⇧4`. Check the fixture for the exact shape of `modifiers`.
3. If `tap` is `null` but `hold` isn't, show the hold action as the main label (e.g. idx 6 on Main is hold-only Left Ctrl).
4. Show the hold action as a small secondary label. For `MO`/`LT`/`TG`/`TO`, use the target layer's **title** (e.g. "Nav").
5. For `KC_TRANSPARENT`, show the label of the same key on the base layer, **dimmed**, so I can see what falls through. `KC_NO` and `null` show as blank, dimmed keys.
6. `QK_LLCK` → `🔒`. `CW_TOGG` → "Caps Word". RGB_* and media keys get short glyphs or labels.

Put all keycode mappings in one table-driven file (`KeycodeLabels.swift`) and unit-test it against every code in the fixture. **No code in the fixture may fall through unmapped.** Unknown codes show the raw code with the `KC_` prefix removed.

### Voyager geometry and key order (verified against the fixture)

- Indices **0–25 = left half**: four rows of 6 (`0–5`, `6–11`, `12–17`, `18–23`, outer column to inner column), then **thumbs `24` (inner) and `25` (outer)**.
- Indices **26–51 = right half**: four rows of 6 (`26–31`, `32–37`, `38–43`, `44–49`, inner column to outer column), then **thumbs `50` (inner) and `51` (outer)**.
- Check: Main idx 0 = Esc, 5 = `5`, 24 = Space/MO(1); idx 26 = `6`, 31 = `-`, 50 = Enter, 51 = Backspace/MO(2).
- Draw two split halves with the Voyager's column stagger (the middle and ring columns sit higher) and the thumb keys angled below the inner columns. It doesn't need to be exact, but it should look like my keyboard so I can match positions by eye.
- A header strip shows the layer title, tinted with the layer's color, with a 🔒 badge if possible. The firmware only reports the layer number, not why it's active, so leave the badge out if it can't be detected reliably.

## Overlay behavior

- Show when the reported layer isn't the base layer (configurable, default 0). Hide when it returns to base.
- It triggers for **every** way of reaching a layer: momentary hold, lock, toggle, one-shot.
- **Show delay** (default ~120 ms) so tapping a dual-role key like Space/MO(1) doesn't flash the overlay. A layer has to stay active that long before the overlay appears. **Fade in and out** (default ~100 ms).
- If the layer changes while visible, swap the contents in place without re-animating the window.
- **Per-layer "never show" list** in Settings, e.g. for a gaming layer. Layers in the list never trigger the overlay. If I switch to one while the overlay is visible, it hides.
- Optional auto-hide timeout (default off).
- Optional stretch goal: use KEYDOWN/KEYUP (col, row) to highlight keys being pressed. This needs the Voyager's matrix → Oryx index mapping (from the QMK `keyboards/zsa/voyager` LAYOUT macro). Only do this after everything else works.

## Settings (applied live)

A Settings window, opened from the menu bar:
- **Overall opacity** (0.1–1.0)
- **Background opacity** and **key fill opacity**, separate from label opacity, so the board can be faint and the text readable
- **Size** (about 40–150% of a default width)
- **Position**: center by default; also top, bottom, or corners, plus X/Y offset
- **Show delay** and **fade duration**
- **Hidden layers**: a checkbox per layer, labeled with the Oryx layer titles
- Show or hide secondary (hold) labels; dim or blank transparent keys
- Theme: dark or light; accent from the layer color or custom
- Oryx layout hash ID; Reload layout
- Window level (advanced)
- Launch at login (`SMAppService.mainApp`, works once the app is bundled)

Store settings as JSON in `~/Library/Application Support/VoyagerView/config.json`. Editing the file by hand should hot-reload.

## Project layout (suggested)

```
Package.swift
Sources/VoyagerView/
  App/        AppDelegate, menu bar, settings window
  Overlay/    OverlayPanel, KeyboardView (SwiftUI), VoyagerGeometry
  Layers/     LayerSource, OryxHIDLayerSource, OryxProtocol (pure encode/decode), DemoLayerSource
  Keymap/     OryxClient, models, KeycodeLabels, LayoutCache
  Config/     Settings model + persistence
Tests/VoyagerViewTests/   protocol parsing, label table, layout decoding, geometry order
Tests/Fixtures/oryx-layout-dMyG6.json
scripts/bundle.sh
```

Keep `OryxProtocol` free of I/O, with packet encode and decode as pure functions, so it can be unit-tested.

## Build order

1. SwiftPM skeleton, menu bar app, `DemoLayerSource`, and a bare overlay panel. **Then ask me to test it over LoL fullscreen.**
2. `OryxHIDLayerSource`: pair, receive layer events, handle reconnects. Log every event at first so I can check the latency by feel.
3. Oryx client, fixture-based decoding, label table and tests.
4. The real keyboard drawing.
5. Settings window and persistence.
6. Bundle script, launch at login, README.

## Definition of done

1. `swift build` and `swift test` pass with Command Line Tools only.
2. `scripts/bundle.sh` produces `VoyagerView.app`, which runs from the menu bar with no Dock icon and **without Keymapp running**.
3. Holding a layer key shows the right layer, centered on the current screen, within the show delay plus about 30 ms. Releasing hides it. Locking a layer keeps it visible until I unlock.
4. It shows over League of Legends **fullscreen**, doesn't take focus, lets clicks through, and causes no noticeable FPS drop or input lag. If fullscreen turns out to be impossible, say so explicitly.
5. Opacity, size, position, and hidden-layer changes apply live.
6. Survives unplugging and replugging the keyboard, and sleep/wake.
7. Demo mode works without the keyboard.
8. The README covers setup, any permissions, and how to change the layout hash ID.

## Working notes for the agent

- Everything marked "verified" above was checked against the real device, API, or source on 2026-11-15. Anything else (macOS window-level behavior over LoL, the Input Monitoring requirement, `IOHIDDeviceSetReport` details) still needs testing.
- Commit in small, logical steps.
- Ask me only for things you can't test yourself: launching LoL, pressing layer keys, checking how it looks.
