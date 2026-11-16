// Pure encode/decode for ZSA's Oryx raw HID protocol (zsa/qmk_modules, oryx/oryx.h + oryx.c).
// No I/O here so it can be unit tested.

public enum OryxProtocol {
    /// RAW_EPSIZE in QMK. Every packet in both directions is exactly this long.
    public static let packetSize = 32
    /// ORYX_STOP_BIT (-2 as uint8_t). Marks the end of the meaningful payload.
    public static let stopByte: UInt8 = 0xFE
    /// ORYX_PROTOCOL_VERSION in the firmware this app was written against.
    public static let expectedProtocolVersion: UInt8 = 0x05

    public static let vendorID = 0x3297
    public static let productID = 0x1977
    public static let rawHIDUsagePage = 0xFF60
    public static let rawHIDUsage = 0x61

    /// Host → keyboard (enum Oryx_Command_Code).
    public enum Command: UInt8, Sendable {
        case getFirmwareVersion = 0x00
        case pairingInit = 0x01
        case pairingValidate = 0x02
        /// Defined in the enum, but note: the current firmware's raw_hid_receive has no case for it,
        /// so the keyboard answers with ERROR(UNKNOWN_COMMAND) and stays paired. We still send it as
        /// a courtesy in case a future firmware honours it.
        case disconnect = 0x03
        case setLayer = 0x04
        case getProtocolVersion = 0xFE
    }

    /// Keyboard → host (enum Oryx_Event_Code).
    public enum EventCode: UInt8, Sendable {
        case firmwareVersion = 0x00
        case pairingInput = 0x01
        case pairingKeyInput = 0x02
        case pairingFailed = 0x03
        case pairingSuccess = 0x04
        case layer = 0x05
        case keyDown = 0x06
        case keyUp = 0x07
        case rgbControl = 0x08
        case toggleSmartLayer = 0x09
        case triggerSmartLayer = 0x0A
        case statusLEDControl = 0x0B
        case automouse = 0x0C
        case protocolVersion = 0xFE
        case error = 0xFF
    }

    public enum ErrorCode: UInt8, Sendable {
        case pairingInitFailed = 0x00
        case pairingInputFailed = 0x01
        case pairingKeyInputFailed = 0x02
        case pairingFailed = 0x03
        case rgbMatrixNotEnabled = 0x04
        case statusLEDOutOfRange = 0x05
        case unknownCommand = 0xFF
    }

    public enum Event: Equatable, Sendable {
        case firmwareVersion(String)
        case pairingSuccess
        case pairingFailed
        case layer(Int)
        case keyDown(col: Int, row: Int)
        case keyUp(col: Int, row: Int)
        case protocolVersion(Int)
        case error(code: UInt8)
        /// Anything we don't care about (RGB, smart layer, pairing challenge from old firmware, …).
        case other(code: UInt8)
    }

    /// Build a 32-byte output packet: [command, params..., 0 padding].
    public static func encode(_ command: Command, params: [UInt8] = []) -> [UInt8] {
        var packet = [UInt8](repeating: 0, count: packetSize)
        packet[0] = command.rawValue
        for (i, p) in params.prefix(packetSize - 1).enumerated() {
            packet[i + 1] = p
        }
        return packet
    }

    /// Decode one input report. Returns nil for empty input.
    /// Tolerates a leading report-ID byte of 0 only when the report is 33 bytes long.
    public static func decode(_ raw: [UInt8]) -> Event? {
        var bytes = raw
        if bytes.count == packetSize + 1, bytes[0] == 0 { bytes.removeFirst() }
        guard let first = bytes.first else { return nil }
        func at(_ i: Int) -> UInt8? { i < bytes.count ? bytes[i] : nil }

        guard let code = EventCode(rawValue: first) else { return .other(code: first) }
        switch code {
        case .layer:
            guard let layer = at(1) else { return nil }
            return .layer(Int(layer))
        case .keyDown, .keyUp:
            guard let col = at(1), let row = at(2) else { return nil }
            return code == .keyDown ? .keyDown(col: Int(col), row: Int(row)) : .keyUp(col: Int(col), row: Int(row))
        case .pairingSuccess:
            return .pairingSuccess
        case .pairingFailed:
            return .pairingFailed
        case .protocolVersion:
            guard let v = at(1) else { return nil }
            return .protocolVersion(Int(v))
        case .error:
            return .error(code: at(1) ?? 0)
        case .firmwareVersion:
            // Firmware copies SERIAL_NUMBER (NUL-terminated) starting at byte 1, and then writes the stop
            // byte over the last character slot. Read printable ASCII until a NUL or the stop byte.
            let payload = bytes.dropFirst().prefix { $0 != 0 && $0 != stopByte }
            return .firmwareVersion(String(decoding: payload, as: UTF8.self))
        default:
            return .other(code: first)
        }
    }
}
