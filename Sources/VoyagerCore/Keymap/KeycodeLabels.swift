// Single table that maps QMK/Oryx keycode names to the short labels drawn on the overlay.
// Every code in Tests/Fixtures/oryx-layout-dMyG6.json must be in here (enforced by a test).
// Unknown codes fall back to the raw name with the `KC_` prefix removed.

public enum KeycodeLabels {
    /// Codes whose label depends on the target layer (MO(n), LT(n, kc), …).
    public static let layerCodes: Set<String> = ["MO", "TG", "TO", "TT", "DF", "OSL", "LT", "LM", "PDF"]

    public static let transparentCodes: Set<String> = ["KC_TRANSPARENT", "KC_TRNS", "_______"]
    public static let noCodes: Set<String> = ["KC_NO", "XXXXXXX"]

    /// The label for a keycode, or nil when it isn't in the table.
    public static func knownLabel(for code: String) -> String? { table[code] }

    /// The label for a keycode, falling back to the raw name without `KC_`.
    public static func label(for code: String) -> String {
        if let l = table[code] { return l }
        if code.hasPrefix("KC_") { return String(code.dropFirst(3)) }
        return code
    }

    public static let table: [String: String] = {
        var t: [String: String] = [:]

        // Letters and digits
        for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" { t["KC_\(c)"] = String(c) }
        for d in 0...9 { t["KC_\(d)"] = "\(d)" }
        // Function keys
        for f in 1...24 { t["KC_F\(f)"] = "F\(f)" }

        let entries: [(String, String)] = [
            // Basic
            ("KC_ESCAPE", "Esc"), ("KC_ESC", "Esc"),
            ("KC_TAB", "Tab"),
            ("KC_SPACE", "Space"), ("KC_SPC", "Space"),
            ("KC_ENTER", "Enter"), ("KC_ENT", "Enter"),
            ("KC_BSPC", "⌫"), ("KC_BACKSPACE", "⌫"),
            ("KC_DELETE", "Del ⌦"), ("KC_DEL", "Del ⌦"),
            ("KC_INSERT", "Ins"), ("KC_INS", "Ins"),
            ("KC_CAPS", "Caps"), ("KC_CAPS_LOCK", "Caps"),
            ("KC_PSCR", "PrtSc"), ("KC_PRINT_SCREEN", "PrtSc"),
            ("KC_SCRL", "ScrLk"), ("KC_PAUS", "Pause"), ("KC_APP", "Menu"), ("KC_APPLICATION", "Menu"),

            // Punctuation (unshifted)
            ("KC_MINUS", "-"), ("KC_MINS", "-"),
            ("KC_EQUAL", "="), ("KC_EQL", "="),
            ("KC_LBRC", "["), ("KC_LEFT_BRACKET", "["),
            ("KC_RBRC", "]"), ("KC_RIGHT_BRACKET", "]"),
            ("KC_BSLS", "\\"), ("KC_BACKSLASH", "\\"),
            ("KC_NUHS", "#"), ("KC_NUBS", "\\"),
            ("KC_SCLN", ";"), ("KC_SEMICOLON", ";"),
            ("KC_QUOTE", "'"), ("KC_QUOT", "'"),
            ("KC_GRAVE", "`"), ("KC_GRV", "`"),
            ("KC_COMMA", ","), ("KC_COMM", ","),
            ("KC_DOT", "."),
            ("KC_SLASH", "/"), ("KC_SLSH", "/"),

            // Shifted symbols
            ("KC_TILD", "~"), ("KC_TILDE", "~"),
            ("KC_EXLM", "!"), ("KC_EXCLAIM", "!"),
            ("KC_AT", "@"),
            ("KC_HASH", "#"),
            ("KC_DLR", "$"), ("KC_DOLLAR", "$"),
            ("KC_PERC", "%"), ("KC_PERCENT", "%"),
            ("KC_CIRC", "^"), ("KC_CIRCUMFLEX", "^"),
            ("KC_AMPR", "&"), ("KC_AMPERSAND", "&"),
            ("KC_ASTR", "*"), ("KC_ASTERISK", "*"),
            ("KC_LPRN", "("), ("KC_LEFT_PAREN", "("),
            ("KC_RPRN", ")"), ("KC_RIGHT_PAREN", ")"),
            ("KC_UNDS", "_"), ("KC_UNDERSCORE", "_"),
            ("KC_PLUS", "+"),
            ("KC_LCBR", "{"), ("KC_LEFT_CURLY_BRACE", "{"),
            ("KC_RCBR", "}"), ("KC_RIGHT_CURLY_BRACE", "}"),
            ("KC_PIPE", "|"),
            ("KC_COLN", ":"), ("KC_COLON", ":"),
            ("KC_DQUO", "\""), ("KC_DOUBLE_QUOTE", "\""), ("KC_DQT", "\""),
            ("KC_LABK", "<"), ("KC_LT", "<"), ("KC_LEFT_ANGLE_BRACKET", "<"),
            ("KC_RABK", ">"), ("KC_GT", ">"), ("KC_RIGHT_ANGLE_BRACKET", ">"),
            ("KC_QUES", "?"), ("KC_QUESTION", "?"),

            // Navigation
            ("KC_LEFT", "←"), ("KC_RIGHT", "→"), ("KC_RGHT", "→"), ("KC_UP", "↑"), ("KC_DOWN", "↓"),
            ("KC_HOME", "Home"), ("KC_END", "End"),
            ("KC_PAGE_UP", "PgUp"), ("KC_PGUP", "PgUp"),
            ("KC_PAGE_DOWN", "PgDn"), ("KC_PGDN", "PgDn"),

            // Modifiers
            ("KC_LEFT_CTRL", "⌃ Ctrl"), ("KC_LCTL", "⌃ Ctrl"), ("KC_RIGHT_CTRL", "⌃ Ctrl"), ("KC_RCTL", "⌃ Ctrl"),
            ("KC_LEFT_SHIFT", "⇧ Shift"), ("KC_LSFT", "⇧ Shift"), ("KC_RIGHT_SHIFT", "⇧ Shift"), ("KC_RSFT", "⇧ Shift"),
            ("KC_LEFT_ALT", "⌥ Alt"), ("KC_LALT", "⌥ Alt"), ("KC_RIGHT_ALT", "⌥ Alt"), ("KC_RALT", "⌥ Alt"),
            ("KC_LEFT_GUI", "⌘ Cmd"), ("KC_LGUI", "⌘ Cmd"), ("KC_RIGHT_GUI", "⌘ Cmd"), ("KC_RGUI", "⌘ Cmd"),
            ("KC_MEH", "Meh"), ("KC_HYPR", "Hyper"),

            // Keypad
            ("KC_KP_PLUS", "+"), ("KC_PPLS", "+"),
            ("KC_KP_MINUS", "-"), ("KC_PMNS", "-"),
            ("KC_KP_ASTERISK", "*"), ("KC_PAST", "*"),
            ("KC_KP_SLASH", "/"), ("KC_PSLS", "/"),
            ("KC_KP_ENTER", "Enter"), ("KC_PENT", "Enter"),
            ("KC_KP_DOT", "."), ("KC_PDOT", "."),
            ("KC_KP_EQUAL", "="), ("KC_PEQL", "="),
            ("KC_KP_COMMA", ","), ("KC_PCMM", ","),
            ("KC_NUM_LOCK", "NumLk"), ("KC_NUM", "NumLk"),

            // Media and system
            ("KC_AUDIO_VOL_UP", "🔊"), ("KC_VOLU", "🔊"), ("KC_KB_VOLUME_UP", "🔊"),
            ("KC_AUDIO_VOL_DOWN", "🔉"), ("KC_VOLD", "🔉"), ("KC_KB_VOLUME_DOWN", "🔉"),
            ("KC_AUDIO_MUTE", "🔇"), ("KC_MUTE", "🔇"), ("KC_KB_MUTE", "🔇"),
            ("KC_MEDIA_PLAY_PAUSE", "⏯"), ("KC_MPLY", "⏯"),
            ("KC_MEDIA_NEXT_TRACK", "⏭"), ("KC_MNXT", "⏭"),
            ("KC_MEDIA_PREV_TRACK", "⏮"), ("KC_MPRV", "⏮"),
            ("KC_MEDIA_STOP", "⏹"), ("KC_MSTP", "⏹"),
            ("KC_MEDIA_FAST_FORWARD", "⏩"), ("KC_MFFD", "⏩"),
            ("KC_MEDIA_REWIND", "⏪"), ("KC_MRWD", "⏪"),
            ("KC_MEDIA_EJECT", "⏏"), ("KC_EJCT", "⏏"),
            ("KC_BRIGHTNESS_UP", "☀︎+"), ("KC_BRIU", "☀︎+"),
            ("KC_BRIGHTNESS_DOWN", "☀︎−"), ("KC_BRID", "☀︎−"),
            ("KC_SYSTEM_SLEEP", "Sleep"), ("KC_SLEP", "Sleep"),
            ("KC_MISSION_CONTROL", "Mission"), ("KC_MCTL", "Mission"),
            ("KC_LAUNCHPAD", "Launchpad"), ("KC_LPAD", "Launchpad"),

            // Mouse keys
            ("KC_MS_UP", "🖱↑"), ("MS_UP", "🖱↑"), ("KC_MS_DOWN", "🖱↓"), ("MS_DOWN", "🖱↓"),
            ("KC_MS_LEFT", "🖱←"), ("MS_LEFT", "🖱←"), ("KC_MS_RIGHT", "🖱→"), ("MS_RGHT", "🖱→"),
            ("KC_MS_BTN1", "Click"), ("MS_BTN1", "Click"), ("KC_MS_BTN2", "R-Click"), ("MS_BTN2", "R-Click"),
            ("KC_MS_BTN3", "M-Click"), ("MS_BTN3", "M-Click"),
            ("KC_MS_WH_UP", "Wheel↑"), ("MS_WHLU", "Wheel↑"), ("KC_MS_WH_DOWN", "Wheel↓"), ("MS_WHLD", "Wheel↓"),

            // RGB matrix / lighting
            ("RGB_TOG", "RGB ⏻"), ("RM_TOGG", "RGB ⏻"),
            ("RGB_MODE_FORWARD", "RGB ▶"), ("RGB_MOD", "RGB ▶"), ("RM_NEXT", "RGB ▶"),
            ("RGB_MODE_REVERSE", "RGB ◀"), ("RGB_RMOD", "RGB ◀"), ("RM_PREV", "RGB ◀"),
            ("RGB_SLD", "RGB ■"),
            ("RGB_VAI", "☀︎+"), ("RM_VALU", "☀︎+"),
            ("RGB_VAD", "☀︎−"), ("RM_VALD", "☀︎−"),
            ("RGB_HUI", "Hue+"), ("RM_HUEU", "Hue+"), ("RGB_HUD", "Hue−"), ("RM_HUED", "Hue−"),
            ("RGB_SAI", "Sat+"), ("RM_SATU", "Sat+"), ("RGB_SAD", "Sat−"), ("RM_SATD", "Sat−"),
            ("RGB_SPI", "Spd+"), ("RM_SPDU", "Spd+"), ("RGB_SPD", "Spd−"), ("RM_SPDD", "Spd−"),
            ("TOGGLE_LAYER_COLOR", "Layer ◐"), ("LED_LEVEL", "LED"),

            // Specials
            ("QK_LLCK", "🔒"), ("QK_LAYER_LOCK", "🔒"),
            ("CW_TOGG", "Caps Word"), ("QK_CAPS_WORD_TOGGLE", "Caps Word"),
            ("QK_BOOT", "Boot"), ("QK_BOOTLOADER", "Boot"),
            ("QK_REP", "Repeat"), ("QK_AREP", "Alt Rep"),
            ("KC_TRANSPARENT", "▽"), ("KC_TRNS", "▽"),
            ("KC_NO", ""),

            // Layer keys: generic fallbacks, the labeler substitutes the target layer title.
            ("MO", "MO"), ("TG", "TG"), ("TO", "TO"), ("TT", "TT"), ("DF", "DF"), ("OSL", "OSL"), ("LT", "LT"), ("LM", "LM"),
            ("OSM", "OSM"),
        ]
        for (k, v) in entries { t[k] = v }
        return t
    }()
}
