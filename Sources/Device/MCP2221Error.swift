import Foundation

/// What can go wrong on the way to the EEPROM.
enum MCP2221Error: LocalizedError, Equatable {

    /// No MCP2221A is attached, or another process holds it open.
    case adapterNotFound

    /// The adapter was found but refused to open. On macOS this is usually a second
    /// process already holding the device.
    case adapterNotOpened(kern_return_t)

    /// A report could not be handed to the adapter.
    case sendFailed(command: String, status: kern_return_t)

    /// The adapter took the report and then said nothing.
    case noReply(command: String)

    /// The adapter answered, but with a different command code than it was asked for.
    case unexpectedResponse(command: UInt8, received: UInt8)

    /// The adapter's I2C engine reported itself busy and stayed busy.
    case engineBusy(command: String)

    /// The addressed chip did not acknowledge. With the board plugged into USB this is
    /// the usual outcome, because the audio chip holds the bus.
    case noAcknowledge(address: UInt8)

    /// The engine did not return to idle within the time allowed.
    case transferTimedOut

    /// The EEPROM answered, but with different bytes than were written.
    case verificationFailed(expected: [UInt8], read: [UInt8])

    var errorDescription: String? {
        switch self {
        case .adapterNotFound:
            return String(localized: "No MCP2221A found. Plug the adapter in, or quit whatever else is using it.")
        case let .adapterNotOpened(status):
            return String(localized: "The adapter could not be opened. IOKit reports status \(Self.hex(status)).")
        case let .sendFailed(command, status):
            return String(localized: "The adapter did not accept the \(command) report. IOKit reports status \(Self.hex(status)).")
        case let .noReply(command):
            return String(localized: "The adapter took the \(command) report and did not answer.")
        case let .unexpectedResponse(command, received):
            return String(localized: "Asked the adapter for command \(Self.hex(command)) and it answered \(Self.hex(received)).")
        case let .engineBusy(command):
            return String(localized: "The adapter stayed busy during \(command).")
        case let .noAcknowledge(address):
            return String(localized: "No chip answered at address \(Self.hex(address)). Unplug the Sound Box from USB: with power on it, the audio chip holds the bus.")
        case .transferTimedOut:
            return String(localized: "The transfer did not finish. The adapter was reset, so try again.")
        case .verificationFailed:
            return String(localized: "The EEPROM read back different bytes than were written.")
        }
    }

    /// IOKit returns a signed value whose bit pattern is what the documentation names,
    /// so it is shown unsigned and padded rather than as a negative number.
    private static func hex(_ value: kern_return_t) -> String {
        String(format: "0x%08X", UInt32(bitPattern: value))
    }

    private static func hex(_ value: UInt8) -> String {
        String(format: "0x%02X", value)
    }
}
