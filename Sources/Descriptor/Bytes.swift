import Foundation

extension UInt8 {

    /// The same byte with its bit order mirrored, so bit 0 swaps with bit 7 and so on.
    ///
    /// The PCM2704C needs this because it clocks the EEPROM in LSB first whilst the
    /// EEPROM shifts every byte out MSB first.
    var bitsReversed: UInt8 {
        var value = self
        value = (value & 0xF0) >> 4 | (value & 0x0F) << 4
        value = (value & 0xCC) >> 2 | (value & 0x33) << 2
        value = (value & 0xAA) >> 1 | (value & 0x55) << 1
        return value
    }
}

enum HexDump {

    /// Render bytes as an offset, hexadecimal and readable characters, sixteen to a line.
    ///
    /// The character column may come from a different array than the hex column, and for
    /// this app it does: the hex shows what sits in the EEPROM, which is mirrored, whilst
    /// the characters show the same bytes the way the audio chip receives them. Column by
    /// column the two agree, so a name can be checked by eye without undoing the mirroring
    /// in one's head.
    ///
    /// What stands in the hex column for a byte nobody has read yet.
    static let unknown = "--"

    /// - Parameters:
    ///   - payload: The bytes to show as hexadecimal. A `nil` is a cell whose content is
    ///     not known, which is what the whole page looks like before a board is read.
    ///   - characters: The bytes to show as text. Defaults to `payload`. A shorter array
    ///     leaves the remaining positions blank.
    /// - Returns: One line per sixteen bytes, without a trailing newline.
    static func string(for payload: [UInt8?], characters: [UInt8?]? = nil) -> String {
        let readable = characters ?? payload
        return stride(from: 0, to: payload.count, by: 16).map { start in
            let upper = min(start + 16, payload.count)
            // A wider gap after eight bytes, the way every hex dump sets it: it gives the
            // eye an anchor without opening a second column.
            let columns = payload[start..<upper].map { byte in
                byte.map { String(format: "%02X", $0) } ?? unknown
            }
            let left = columns.prefix(8).joined(separator: " ")
            let right = columns.dropFirst(8).joined(separator: " ")
            let hex = (right.isEmpty ? left : "\(left)   \(right)")
                .padding(toLength: 49, withPad: " ", startingAt: 0)
            let text = (start..<upper).map { index -> Character in
                guard index < readable.count, let byte = readable[index] else { return " " }
                return (0x20..<0x7F).contains(byte) ? Character(UnicodeScalar(byte)) : "."
            }
            return String(format: "%02X  %@  %@", start, hex, String(text))
        }
        .joined(separator: "\n")
    }

    /// The same, for bytes that are all known.
    static func string(for payload: [UInt8], characters: [UInt8]? = nil) -> String {
        string(for: payload.map(Optional.some), characters: characters?.map(Optional.some))
    }
}
