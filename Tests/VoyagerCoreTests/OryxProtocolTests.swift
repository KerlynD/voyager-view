import Testing
@testable import VoyagerCore

@Suite struct OryxProtocolTests {
    @Test func encodePadsTo32Bytes() {
        let p = OryxProtocol.encode(.pairingInit)
        #expect(p.count == 32)
        #expect(p[0] == 0x01)
        #expect(p.dropFirst().allSatisfy { $0 == 0 })
    }

    @Test func encodeWithParams() {
        let p = OryxProtocol.encode(.setLayer, params: [1, 3])
        #expect(Array(p.prefix(3)) == [0x04, 1, 3])
        #expect(p.count == 32)
    }

    @Test func commandCodesMatchFirmware() {
        #expect(OryxProtocol.Command.getFirmwareVersion.rawValue == 0x00)
        #expect(OryxProtocol.Command.disconnect.rawValue == 0x03)
        #expect(OryxProtocol.Command.getProtocolVersion.rawValue == 0xFE)
    }

    private func packet(_ head: [UInt8]) -> [UInt8] { head + Array(repeating: 0, count: 32 - head.count) }

    @Test func decodeLayer() {
        #expect(OryxProtocol.decode(packet([0x05, 3, 0xFE])) == .layer(3))
    }

    @Test func decodeLayerWithLeadingReportID() {
        #expect(OryxProtocol.decode([0] + packet([0x05, 2, 0xFE])) == .layer(2))
    }

    @Test func decodeKeyEvents() {
        #expect(OryxProtocol.decode(packet([0x06, 4, 7, 0xFE])) == .keyDown(col: 4, row: 7))
        #expect(OryxProtocol.decode(packet([0x07, 4, 7, 0xFE])) == .keyUp(col: 4, row: 7))
    }

    @Test func decodePairingAndVersion() {
        #expect(OryxProtocol.decode(packet([0x04, 0xFE])) == .pairingSuccess)
        #expect(OryxProtocol.decode(packet([0x03, 0xFE])) == .pairingFailed)
        #expect(OryxProtocol.decode(packet([0xFE, 0x05, 0xFE])) == .protocolVersion(5))
        #expect(OryxProtocol.decode(packet([0xFF, 0xFF])) == .error(code: 0xFF))
    }

    @Test func decodeFirmwareVersion() {
        // Firmware writes the serial at byte 1 then overwrites the slot after it with the stop byte.
        let serial = Array("dMyG6/Kre5EL".utf8)
        #expect(OryxProtocol.decode(packet([0x00] + serial + [0xFE])) == .firmwareVersion("dMyG6/Kre5EL"))
    }

    @Test func decodeUnknownAndEmpty() {
        #expect(OryxProtocol.decode([]) == nil)
        #expect(OryxProtocol.decode(packet([0x08, 1])) == .other(code: 0x08))
        #expect(OryxProtocol.decode(packet([0x42])) == .other(code: 0x42))
    }

    @Test func decodeTruncatedLayerIsNil() {
        #expect(OryxProtocol.decode([0x05]) == nil)
    }
}

@Suite struct LayerLockTrackerTests {
    @Test func lockAndUnlock() {
        var t = LayerLockTracker()
        t.layerChanged(to: 1)
        #expect(!t.isCurrentLayerLocked)
        t.keyPressed(code: "QK_LLCK")
        #expect(t.isCurrentLayerLocked)
        t.layerChanged(to: 3) // hold another layer on top
        #expect(!t.isCurrentLayerLocked)
        t.layerChanged(to: 1)
        #expect(t.isCurrentLayerLocked)
        t.keyPressed(code: "QK_LLCK")
        t.layerChanged(to: 0)
        #expect(t.lockedLayers.isEmpty)
    }

    @Test func baseClearsLocks() {
        var t = LayerLockTracker()
        t.layerChanged(to: 2)
        t.keyPressed(code: "QK_LLCK")
        t.layerChanged(to: 0)
        t.layerChanged(to: 2)
        #expect(!t.isCurrentLayerLocked)
    }

    @Test func otherKeysIgnored() {
        var t = LayerLockTracker()
        t.layerChanged(to: 1)
        t.keyPressed(code: "KC_A")
        t.keyPressed(code: nil)
        #expect(!t.isCurrentLayerLocked)
    }
}
