import Foundation
import IOKit
import IOKit.hid
import VoyagerCore

/// Talks to the Voyager's raw HID interface (usage page 0xFF60, usage 0x61) using the Oryx protocol.
///
/// Threading:
/// - A dedicated thread runs its own CFRunLoop with the IOHIDManager scheduled on it. Input reports are
///   copied, decoded (a few byte comparisons) and handed to the main queue. Nothing else happens there,
///   so the endpoint is always drained and the firmware's `send_report` never waits on us.
/// - Writes (32-byte output reports) go through a separate serial queue so a slow write can never
///   delay reading.
/// - All callbacks (`onLayer`, `onKey`, `onStatus`) fire on the main thread.
final class OryxHIDLayerSource: LayerSource {
    var onLayer: ((Int) -> Void)?
    var onKey: ((Int, Bool) -> Void)?
    var onStatus: ((LayerSourceStatus) -> Void)?
    /// Log every KEYDOWN/KEYUP (layer events are always logged).
    var logKeyEvents = false

    // HID thread state
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private let reportBufferSize = 64
    private let reportBuffer: UnsafeMutablePointer<UInt8>

    // Write state
    private let writeQueue = DispatchQueue(label: "com.voyagerview.hid.write", qos: .userInitiated)
    private let lock = NSLock()
    private var writeDevice: IOHIDDevice?

    // Main thread state
    private(set) var status: LayerSourceStatus = .idle
    private var protocolVersion: Int?
    private var pairingAttempts = 0
    private var pairingWatchdog: DispatchWorkItem?
    private var lastLayerEventAt: Date?

    init() {
        reportBuffer = .allocate(capacity: reportBufferSize)
        reportBuffer.initialize(repeating: 0, count: reportBufferSize)
    }

    deinit {
        stop()
        reportBuffer.deallocate()
    }

    // MARK: Lifecycle

    func start() {
        guard thread == nil else { return }
        let ready = DispatchSemaphore(value: 0)
        let t = Thread { [unowned self] in
            self.runLoop = CFRunLoopGetCurrent()
            ready.signal()
            self.hidThreadMain()
        }
        t.name = "VoyagerView.HID"
        t.qualityOfService = .userInteractive
        thread = t
        t.start()
        ready.wait()
    }

    /// Sends DISCONNECT (synchronously, so it goes out before we stop reading) and tears down the thread.
    func stop() {
        guard thread != nil else { return }
        sendSync(.disconnect)
        if let rl = runLoop {
            CFRunLoopPerformBlock(rl, CFRunLoopMode.defaultMode.rawValue) { CFRunLoopStop(CFRunLoopGetCurrent()) }
            CFRunLoopWakeUp(rl)
        }
        thread = nil
        runLoop = nil
        setStatus(.idle)
    }

    /// Re-pair, e.g. after the Mac wakes. PAIRING_INIT is idempotent and makes the firmware send the layer.
    func repair() {
        DispatchQueue.main.async { [self] in
            pairingAttempts = 0
            beginPairing()
        }
    }

    /// Tell the firmware we're going away (before sleep). See OryxProtocol.Command.disconnect for caveats.
    func prepareForSleep() {
        sendSync(.disconnect)
    }

    // MARK: HID thread

    private func hidThreadMain() {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = mgr
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: OryxProtocol.vendorID,
            kIOHIDProductIDKey: OryxProtocol.productID,
            kIOHIDPrimaryUsagePageKey: OryxProtocol.rawHIDUsagePage,
            kIOHIDPrimaryUsageKey: OryxProtocol.rawHIDUsage,
        ]
        IOHIDManagerSetDeviceMatching(mgr, matching as CFDictionary)

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, { ctx, _, _, device in
            guard let ctx else { return }
            Unmanaged<OryxHIDLayerSource>.fromOpaque(ctx).takeUnretainedValue().deviceMatched(device)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, { ctx, _, _, device in
            guard let ctx else { return }
            Unmanaged<OryxHIDLayerSource>.fromOpaque(ctx).takeUnretainedValue().deviceRemoved(device)
        }, ctx)

        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        // Non-exclusive open so Keymapp / Oryx in a browser can still connect.
        let result = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        Log.info("HID manager open: \(Self.describe(result)); Input Monitoring access: \(Self.describe(access))")
        if result == kIOReturnNotPermitted {
            DispatchQueue.main.async { self.setStatus(.permissionDenied) }
        } else if device == nil {
            DispatchQueue.main.async { if self.status == .idle { self.setStatus(.searching) } }
        }

        CFRunLoopRun()

        // Torn down by stop().
        if let d = device {
            IOHIDDeviceRegisterInputReportCallback(d, reportBuffer, reportBufferSize, nil, nil)
        }
        device = nil
        lock.withLock { writeDevice = nil }
        IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = nil
        Log.info("HID thread stopped")
    }

    private func deviceMatched(_ d: IOHIDDevice) {
        if device != nil {
            Log.info("Ignoring a second matching Voyager raw HID interface")
            return
        }
        device = d
        lock.withLock { writeDevice = d }

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(d, reportBuffer, reportBufferSize, { ctx, _, _, _, _, report, length in
            guard let ctx else { return }
            // Hot path: copy, decode, hand off. No logging or UI here.
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            guard let event = OryxProtocol.decode(bytes) else { return }
            let me = Unmanaged<OryxHIDLayerSource>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { me.handle(event) }
        }, ctx)

        let product = IOHIDDeviceGetProperty(d, kIOHIDProductKey as CFString) as? String ?? "?"
        let maxOut = IOHIDDeviceGetProperty(d, kIOHIDMaxOutputReportSizeKey as CFString) as? Int ?? -1
        let maxIn = IOHIDDeviceGetProperty(d, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? -1
        Log.info("Voyager raw HID matched: \(product), max in/out report \(maxIn)/\(maxOut) bytes")

        DispatchQueue.main.async { [self] in
            setStatus(.connected)
            pairingAttempts = 0
            send(.getProtocolVersion)
            beginPairing()
        }
    }

    private func deviceRemoved(_ d: IOHIDDevice) {
        guard let current = device, CFEqual(current, d) else { return }
        device = nil
        lock.withLock { writeDevice = nil }
        Log.info("Voyager raw HID removed")
        DispatchQueue.main.async { [self] in
            pairingWatchdog?.cancel()
            protocolVersion = nil
            setStatus(.searching)
            // Keyboard gone: whatever layer it was on no longer applies.
            onLayer?(0)
        }
    }

    // MARK: Main thread

    private func beginPairing() {
        pairingWatchdog?.cancel()
        guard lock.withLock({ writeDevice != nil }) else { return }
        pairingAttempts += 1
        send(.pairingInit)
        // Firmware answers immediately. If nothing comes back, try again a few times.
        let item = DispatchWorkItem { [weak self] in
            guard let self, case .connected = self.status, self.pairingAttempts < 5 else { return }
            Log.info("No PAIRING_SUCCESS yet, retrying (attempt \(self.pairingAttempts + 1))")
            self.beginPairing()
        }
        pairingWatchdog = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: item)
    }

    private func handle(_ event: OryxProtocol.Event) {
        switch event {
        case .layer(let layer):
            let now = Date()
            let delta = lastLayerEventAt.map { String(format: " (+%.0f ms)", now.timeIntervalSince($0) * 1000) } ?? ""
            lastLayerEventAt = now
            Log.info("LAYER \(layer)\(delta)")
            onLayer?(layer)
        case .keyDown(let col, let row), .keyUp(let col, let row):
            let down: Bool = { if case .keyDown = event { return true } else { return false } }()
            let index = VoyagerGeometry.index(matrixRow: row, col: col)
            if logKeyEvents { Log.info("\(down ? "KEYDOWN" : "KEYUP  ") col \(col) row \(row) → idx \(index.map(String.init) ?? "?")") }
            if let index { onKey?(index, down) }
        case .pairingSuccess:
            pairingWatchdog?.cancel()
            Log.info("PAIRING_SUCCESS")
            setStatus(.paired(protocolVersion: protocolVersion))
        case .pairingFailed:
            Log.error("PAIRING_FAILED")
            setStatus(.connected)
        case .protocolVersion(let v):
            protocolVersion = v
            if v == Int(OryxProtocol.expectedProtocolVersion) {
                Log.info("Oryx protocol version \(v)")
            } else {
                Log.error("Oryx protocol version \(v), expected \(OryxProtocol.expectedProtocolVersion). Things may not work.")
            }
            if case .paired = status { setStatus(.paired(protocolVersion: v)) }
        case .firmwareVersion(let s):
            Log.info("Firmware version \(s)")
        case .error(let code):
            // DISCONNECT isn't implemented by the firmware and comes back as UNKNOWN_COMMAND (0xFF).
            Log.info("Oryx ERROR event, code 0x\(String(code, radix: 16))")
        case .other(let code):
            if logKeyEvents { Log.info("Oryx event 0x\(String(code, radix: 16)) ignored") }
        }
    }

    private func setStatus(_ s: LayerSourceStatus) {
        guard s != status else { return }
        status = s
        onStatus?(s)
    }

    // MARK: Writes

    private func send(_ command: OryxProtocol.Command, params: [UInt8] = []) {
        writeQueue.async { [self] in write(command, params: params) }
    }

    private func sendSync(_ command: OryxProtocol.Command) {
        writeQueue.sync { write(command, params: []) }
    }

    /// Runs on writeQueue.
    private func write(_ command: OryxProtocol.Command, params: [UInt8]) {
        guard let d = lock.withLock({ writeDevice }) else { return }
        let packet = OryxProtocol.encode(command, params: params)
        // QMK raw HID has no report IDs: report ID 0 and exactly 32 bytes.
        let r = packet.withUnsafeBufferPointer { buf in
            IOHIDDeviceSetReport(d, kIOHIDReportTypeOutput, 0, buf.baseAddress!, buf.count)
        }
        if r != kIOReturnSuccess {
            Log.error("Sending \(command) failed: \(Self.describe(r))")
        }
    }

    // MARK: Helpers

    static func describe(_ r: IOReturn) -> String {
        switch r {
        case kIOReturnSuccess: return "success"
        case kIOReturnNotPermitted: return "not permitted"
        case kIOReturnExclusiveAccess: return "exclusive access"
        case kIOReturnNoDevice: return "no device"
        case kIOReturnNotOpen: return "not open"
        case kIOReturnTimeout: return "timeout"
        default: return String(format: "0x%08x", UInt32(bitPattern: r))
        }
    }

    static func describe(_ a: IOHIDAccessType) -> String {
        switch a {
        case kIOHIDAccessTypeGranted: return "granted"
        case kIOHIDAccessTypeDenied: return "denied"
        default: return "not determined"
        }
    }
}
