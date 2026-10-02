import Foundation

/// What can go wrong whilst assembling the descriptor block.
///
/// Every case carries the figures a person needs to correct the entry, because these
/// reach the window as the message beside the field.
enum DescriptorError: LocalizedError, Equatable {

    /// Which text field a complaint is about.
    ///
    /// A case rather than a string, so the name a person reads is translated in the same
    /// place as the rest of the window.
    enum Field: Equatable {
        case productName
        case manufacturer
        case serialNumber

        var name: String {
            switch self {
            case .productName: return String(localized: "Product name")
            case .manufacturer: return String(localized: "Manufacturer")
            case .serialNumber: return String(localized: "Serial number")
            }
        }
    }

    /// A string does not fit its fixed-width field.
    case stringTooLong(field: Field, limit: Int, actual: Int)

    /// A string carries a character outside ASCII. The chip transmits the bytes as they
    /// are and the host reads them as Unicode, so anything above 0x7F arrives wrong.
    case stringNotASCII(field: Field)

    /// The assembled block missed its prescribed length, which means the layout above is
    /// wrong rather than the input.
    case wrongBlockLength(Int)

    var errorDescription: String? {
        switch self {
        case let .stringTooLong(field, limit, actual):
            return String(localized: "\(field.name) is \(actual) characters long, and the field holds \(limit).")
        case let .stringNotASCII(field):
            return String(localized: "\(field.name) carries a character the chip cannot transmit. Use plain ASCII.")
        case let .wrongBlockLength(actual):
            return String(localized: "Assembled \(actual) bytes instead of \(DescriptorBlock.length).")
        }
    }
}
