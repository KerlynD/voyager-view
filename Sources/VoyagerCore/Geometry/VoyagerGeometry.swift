import CoreGraphics

/// Physical key positions of the ZSA Voyager, indexed by Oryx key index (0–51).
/// Generated from zsa/qmk_firmware (branch firmware25) keyboards/zsa/voyager/keyboard.json, whose
/// LAYOUT labels `kNN` are exactly the Oryx indices. Units are key widths (1u = one key).
public enum VoyagerGeometry {
    public struct Key: Equatable, Sendable {
        public let index: Int
        /// Position of the key's top-left corner in keyboard.json units.
        public let x: Double
        public let y: Double
        /// QMK matrix position, as reported by Oryx KEYDOWN/KEYUP events (which send col, row).
        public let matrixRow: Int
        public let matrixCol: Int

        public var isLeftHalf: Bool { index < 26 }
        public var isThumb: Bool { [24, 25, 50, 51].contains(index) }
    }

    public static let keys: [Key] = [
        Key(index: 0, x: 0, y: 0.5, matrixRow: 0, matrixCol: 1),
        Key(index: 1, x: 1, y: 0.5, matrixRow: 0, matrixCol: 2),
        Key(index: 2, x: 2, y: 0.25, matrixRow: 0, matrixCol: 3),
        Key(index: 3, x: 3, y: 0, matrixRow: 0, matrixCol: 4),
        Key(index: 4, x: 4, y: 0.25, matrixRow: 0, matrixCol: 5),
        Key(index: 5, x: 5, y: 0.5, matrixRow: 0, matrixCol: 6),
        Key(index: 6, x: 0, y: 1.5, matrixRow: 1, matrixCol: 1),
        Key(index: 7, x: 1, y: 1.5, matrixRow: 1, matrixCol: 2),
        Key(index: 8, x: 2, y: 1.25, matrixRow: 1, matrixCol: 3),
        Key(index: 9, x: 3, y: 1, matrixRow: 1, matrixCol: 4),
        Key(index: 10, x: 4, y: 1.25, matrixRow: 1, matrixCol: 5),
        Key(index: 11, x: 5, y: 1.5, matrixRow: 1, matrixCol: 6),
        Key(index: 12, x: 0, y: 2.5, matrixRow: 2, matrixCol: 1),
        Key(index: 13, x: 1, y: 2.5, matrixRow: 2, matrixCol: 2),
        Key(index: 14, x: 2, y: 2.25, matrixRow: 2, matrixCol: 3),
        Key(index: 15, x: 3, y: 2, matrixRow: 2, matrixCol: 4),
        Key(index: 16, x: 4, y: 2.25, matrixRow: 2, matrixCol: 5),
        Key(index: 17, x: 5, y: 2.5, matrixRow: 2, matrixCol: 6),
        Key(index: 18, x: 0, y: 3.5, matrixRow: 3, matrixCol: 1),
        Key(index: 19, x: 1, y: 3.5, matrixRow: 3, matrixCol: 2),
        Key(index: 20, x: 2, y: 3.25, matrixRow: 3, matrixCol: 3),
        Key(index: 21, x: 3, y: 3, matrixRow: 3, matrixCol: 4),
        Key(index: 22, x: 4, y: 3.25, matrixRow: 3, matrixCol: 5),
        Key(index: 23, x: 5, y: 3.5, matrixRow: 4, matrixCol: 4),
        Key(index: 24, x: 5, y: 4.5, matrixRow: 5, matrixCol: 0),
        Key(index: 25, x: 6, y: 4.75, matrixRow: 5, matrixCol: 1),
        Key(index: 26, x: 10, y: 0.5, matrixRow: 6, matrixCol: 0),
        Key(index: 27, x: 11, y: 0.25, matrixRow: 6, matrixCol: 1),
        Key(index: 28, x: 12, y: 0, matrixRow: 6, matrixCol: 2),
        Key(index: 29, x: 13, y: 0.25, matrixRow: 6, matrixCol: 3),
        Key(index: 30, x: 14, y: 0.5, matrixRow: 6, matrixCol: 4),
        Key(index: 31, x: 15, y: 0.5, matrixRow: 6, matrixCol: 5),
        Key(index: 32, x: 10, y: 1.5, matrixRow: 7, matrixCol: 0),
        Key(index: 33, x: 11, y: 1.25, matrixRow: 7, matrixCol: 1),
        Key(index: 34, x: 12, y: 1, matrixRow: 7, matrixCol: 2),
        Key(index: 35, x: 13, y: 1.25, matrixRow: 7, matrixCol: 3),
        Key(index: 36, x: 14, y: 1.5, matrixRow: 7, matrixCol: 4),
        Key(index: 37, x: 15, y: 1.5, matrixRow: 7, matrixCol: 5),
        Key(index: 38, x: 10, y: 2.5, matrixRow: 8, matrixCol: 0),
        Key(index: 39, x: 11, y: 2.25, matrixRow: 8, matrixCol: 1),
        Key(index: 40, x: 12, y: 2, matrixRow: 8, matrixCol: 2),
        Key(index: 41, x: 13, y: 2.25, matrixRow: 8, matrixCol: 3),
        Key(index: 42, x: 14, y: 2.5, matrixRow: 8, matrixCol: 4),
        Key(index: 43, x: 15, y: 2.5, matrixRow: 8, matrixCol: 5),
        Key(index: 44, x: 10, y: 3.5, matrixRow: 10, matrixCol: 2),
        Key(index: 45, x: 11, y: 3.25, matrixRow: 9, matrixCol: 1),
        Key(index: 46, x: 12, y: 3, matrixRow: 9, matrixCol: 2),
        Key(index: 47, x: 13, y: 3.25, matrixRow: 9, matrixCol: 3),
        Key(index: 48, x: 14, y: 3.5, matrixRow: 9, matrixCol: 4),
        Key(index: 49, x: 15, y: 3.5, matrixRow: 9, matrixCol: 5),
        Key(index: 50, x: 9, y: 4.75, matrixRow: 11, matrixCol: 5),
        Key(index: 51, x: 10, y: 4.5, matrixRow: 11, matrixCol: 6),
    ]

    /// keyboard.json puts the halves 4u apart; the drawing pulls the right half in by this much.
    public static let rightHalfShift: Double = 1.5
    /// Thumb keys are drawn rotated by this many degrees (left half clockwise, right half mirrored).
    public static let thumbRotationDegrees: Double = 15

    /// Where to draw a key, in units, after closing the gap between halves.
    public static func drawOrigin(of key: Key) -> CGPoint {
        CGPoint(x: key.isLeftHalf ? key.x : key.x - rightHalfShift, y: key.y)
    }

    /// Total drawing size in units.
    public static var drawSize: CGSize {
        let maxX = keys.map { drawOrigin(of: $0).x + 1 }.max() ?? 0
        let maxY = keys.map { $0.y + 1 }.max() ?? 0
        return CGSize(width: maxX, height: maxY)
    }

    public static func rotationDegrees(of key: Key) -> Double {
        guard key.isThumb else { return 0 }
        return key.isLeftHalf ? thumbRotationDegrees : -thumbRotationDegrees
    }

    /// Oryx key index for a KEYDOWN/KEYUP matrix position.
    public static func index(matrixRow row: Int, col: Int) -> Int? {
        matrixLookup[MatrixPos(row: row, col: col)]
    }

    private struct MatrixPos: Hashable { let row: Int; let col: Int }
    private static let matrixLookup: [MatrixPos: Int] = Dictionary(
        uniqueKeysWithValues: keys.map { (MatrixPos(row: $0.matrixRow, col: $0.matrixCol), $0.index) }
    )
}
