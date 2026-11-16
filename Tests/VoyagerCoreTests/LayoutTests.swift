import Foundation
import Testing
@testable import VoyagerCore

enum Fixture {
    static let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/oryx-layout-dMyG6.json")

    static let layout: OryxLayout = {
        let data = try! Data(contentsOf: url)
        return try! OryxLayout.decodeGraphQLResponse(data)
    }()

    /// Every action code that appears anywhere in the fixture.
    static var allCodes: Set<String> {
        var codes = Set<String>()
        for layer in layout.layers {
            for key in layer.keys {
                for a in [key.tap, key.hold, key.doubleTap, key.tapHold] {
                    if let a { codes.insert(a.code) }
                }
            }
        }
        return codes
    }
}

@Suite struct LayoutDecodingTests {
    @Test func decodesFixture() {
        let l = Fixture.layout
        #expect(l.title == "angel 3 layer")
        #expect(l.geometry == "voyager")
        #expect(l.layers.map(\.title) == ["Main", "Symbols", "Medi/Sys", "Nav"])
        #expect(l.layers.map(\.color) == ["#fff4d4", "#FFE3B8", "#E3A23B", "#2E4A9E"])
        #expect(l.layers.allSatisfy { $0.keys.count == 52 })
    }

    @Test func keyOrderMatchesSpec() {
        let main = Fixture.layout.layers[0].keys
        #expect(main[0].tap?.code == "KC_ESCAPE")
        #expect(main[5].tap?.code == "KC_5")
        #expect(main[24].tap?.code == "KC_SPACE")
        #expect(main[24].hold?.code == "MO")
        #expect(main[24].hold?.layer == 1)
        #expect(main[26].tap?.code == "KC_6")
        #expect(main[31].tap?.code == "KC_MINUS")
        #expect(main[50].tap?.code == "KC_ENTER")
        #expect(main[51].tap?.code == "KC_BSPC")
        #expect(main[51].hold?.layer == 2)
        #expect(main[25].tap == nil)
        #expect(main[25].hold?.layer == 3)
    }

    @Test func decodesModifiers() {
        let nav = Fixture.layout.layers[3].keys
        let screenshot = nav[11].tap!
        #expect(screenshot.code == "KC_4")
        #expect(screenshot.modifiers?.gui == true)
        #expect(screenshot.modifiers?.shift == true)
        #expect(screenshot.modifiers?.ctrl == true)
        #expect(screenshot.modifiers?.alt == false)
    }

    @Test func graphQLErrorsThrow() {
        let body = #"{"data":{"layout":null},"errors":[{"message":"Layout not found"}]}"#
        #expect(throws: OryxLayout.LayoutError.self) {
            try OryxLayout.decodeGraphQLResponse(Data(body.utf8))
        }
    }

    @Test func roundTripsThroughCodable() throws {
        let data = try JSONEncoder().encode(Fixture.layout)
        let back = try JSONDecoder().decode(OryxLayout.self, from: data)
        #expect(back == Fixture.layout)
    }
}

@Suite struct KeycodeLabelTests {
    @Test func everyFixtureCodeIsMapped() {
        let unmapped = Fixture.allCodes.filter { KeycodeLabels.knownLabel(for: $0) == nil }.sorted()
        #expect(unmapped.isEmpty, "Unmapped codes: \(unmapped)")
    }

    @Test func unknownCodeFallsBackToRawName() {
        #expect(KeycodeLabels.label(for: "KC_WWW_SEARCH") == "WWW_SEARCH")
        #expect(KeycodeLabels.label(for: "QK_SOMETHING") == "QK_SOMETHING")
    }

    @Test func specials() {
        #expect(KeycodeLabels.label(for: "QK_LLCK") == "🔒")
        #expect(KeycodeLabels.label(for: "CW_TOGG") == "Caps Word")
        #expect(KeycodeLabels.label(for: "KC_DQUO") == "\"")
        #expect(KeycodeLabels.label(for: "KC_BSLS") == "\\")
    }
}

@Suite struct KeyLabelerTests {
    let layout = Fixture.layout

    func caps(_ layer: Int) -> [KeyCap] { KeyLabeler.caps(forLayer: layer, in: layout) }

    @Test func fiftyTwoCapsPerLayer() {
        for l in 0..<4 { #expect(caps(l).count == 52) }
        #expect(caps(9).allSatisfy { $0 == .blank })
    }

    @Test func modifierGlyphs() {
        let a = OryxAction(code: "KC_4", modifiers: OryxModifiers(leftShift: true, leftGui: true))
        #expect(KeyLabeler.actionLabel(a, layout: layout) == "⌘⇧4")
    }

    @Test func customLabelWins() {
        let nav = caps(3)
        #expect(nav[21].primary == "copy")
        #expect(nav[22].primary == "paste")
        #expect(nav[11].primary == "Screenshot")
        #expect(caps(2)[45].primary == "claude")
        #expect(caps(2)[46].primary == "wispr flow")
    }

    @Test func emojiUsedWhenNoCustomLabel() {
        #expect(caps(3)[16].primary == "🔍")
    }

    @Test func modifiedTapWithoutCustomLabel() {
        #expect(caps(3)[6].primary == "⌘Tab")
        #expect(caps(2)[34].primary == "⌃↑")
        // Empty modifiers object shows the bare key.
        #expect(caps(3)[34].primary == "↑")
    }

    @Test func holdOnlyKeyShowsHoldAsPrimary() {
        let main = caps(0)
        #expect(main[6].primary == "⌃ Ctrl")
        #expect(main[6].secondary == nil)
        #expect(main[25].primary == "Nav")
    }

    @Test func holdAsSecondaryWithLayerTitles() {
        let main = caps(0)
        #expect(main[24] == KeyCap(primary: "Space", secondary: "Symbols"))
        #expect(main[51] == KeyCap(primary: "⌫", secondary: "Medi/Sys"))
        #expect(main[0] == KeyCap(primary: "Esc", secondary: "Tab"))
        #expect(main[43].secondary == "⇧ Shift")
    }

    @Test func transparentShowsBaseDimmed() {
        let sym = caps(1)
        #expect(sym[24] == KeyCap(primary: "Space", secondary: "Symbols", style: .transparent))
        #expect(sym[18] == KeyCap(primary: "⌘ Cmd", style: .transparent))
        #expect(caps(2)[26] == KeyCap(primary: "6", style: .transparent))
    }

    @Test func noAndNullAreBlank() {
        #expect(caps(2)[7] == .blank)   // KC_NO
        #expect(caps(1)[6] == .blank)   // null tap and hold
        #expect(caps(3)[1] == .blank)
    }

    @Test func layerLockKey() {
        for l in 1...3 { #expect(caps(l)[0].primary == "🔒") }
    }

    @Test func noRawFallbackLabelsInFixture() {
        // Nothing in the fixture should render as a raw keycode name.
        for l in 0..<4 {
            for cap in caps(l) {
                #expect(!cap.primary.contains("KC_") && !cap.primary.contains("QK_") && !cap.primary.contains("RGB_"),
                        "layer \(l): \(cap.primary)")
            }
        }
    }
}

@Suite struct GeometryTests {
    @Test func fiftyTwoKeysInIndexOrder() {
        #expect(VoyagerGeometry.keys.count == 52)
        #expect(VoyagerGeometry.keys.map(\.index) == Array(0..<52))
    }

    @Test func halvesAndThumbs() {
        let k = VoyagerGeometry.keys
        #expect(k[0..<26].allSatisfy { $0.isLeftHalf })
        #expect(k[26..<52].allSatisfy { !$0.isLeftHalf })
        #expect(k.filter(\.isThumb).map(\.index) == [24, 25, 50, 51])
        // Left rows run outer→inner (x increasing), right rows inner→outer (x increasing too).
        for row in 0..<4 {
            let left = (0..<6).map { k[row * 6 + $0].x }
            let right = (0..<6).map { k[26 + row * 6 + $0].x }
            #expect(left == left.sorted())
            #expect(right == right.sorted())
        }
        // Thumbs sit below the bottom row.
        #expect(k[24].y > k[23].y && k[50].y > k[44].y)
    }

    @Test func middleColumnSitsHighest() {
        let k = VoyagerGeometry.keys
        #expect(k[3].y < k[2].y && k[3].y < k[4].y && k[2].y < k[1].y)
        #expect(k[28].y < k[27].y && k[28].y < k[29].y)
    }

    @Test func matrixLookupIsBijective() {
        for key in VoyagerGeometry.keys {
            #expect(VoyagerGeometry.index(matrixRow: key.matrixRow, col: key.matrixCol) == key.index)
        }
        #expect(VoyagerGeometry.index(matrixRow: 99, col: 0) == nil)
    }

    @Test func drawSizeIsReasonable() {
        let s = VoyagerGeometry.drawSize
        #expect(s.width > 14 && s.width < 16)
        #expect(s.height > 5 && s.height < 6)
    }
}

@Suite struct SettingsTests {
    @Test func defaults() {
        let s = AppSettings.defaults
        #expect(s.layoutHashId == "dMyG6")
        #expect(s.showDelayMs == 120)
        #expect(s.fadeDurationMs == 100)
        #expect(s.windowLevel == .shielding)
        #expect(s.position == .center)
    }

    @Test func lenientDecodeKeepsGoodKeys() {
        let json = #"{"scale": 1.2, "theme": "purple", "hiddenLayers": [2, 2, -1], "overallOpacity": 9, "bogus": true}"#
        let s = AppSettings.decodeLenient(Data(json.utf8))
        #expect(s.scale == 1.2)
        #expect(s.theme == .dark)          // invalid enum → default
        #expect(s.hiddenLayers == [2])     // deduped, negatives dropped
        #expect(s.overallOpacity == 1.0)   // clamped
    }

    @Test func garbageDecodesToDefaults() {
        #expect(AppSettings.decodeLenient(Data("not json".utf8)) == .defaults)
    }

    @Test func roundTrip() throws {
        var s = AppSettings.defaults
        s.hiddenLayers = [3]
        s.position = .bottomRight
        let back = AppSettings.decodeLenient(try s.encodedJSON())
        #expect(back == s)
    }

    @Test func visibilityRules() {
        var s = AppSettings.defaults
        #expect(!s.shouldShowOverlay(forLayer: 0))
        #expect(s.shouldShowOverlay(forLayer: 1))
        s.hiddenLayers = [1]
        #expect(!s.shouldShowOverlay(forLayer: 1))
        s.baseLayer = 2
        #expect(s.shouldShowOverlay(forLayer: 0))
        #expect(!s.shouldShowOverlay(forLayer: 2))
    }
}
