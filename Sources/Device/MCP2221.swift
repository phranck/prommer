import Foundation
import IOKit
import IOKit.hid

/// An MCP2221A reached over USB HID, used here as a USB to I2C bridge.
///
/// The chip carries two independent interfaces. The CDC side appears as a serial port and
/// belongs to its UART; I2C lives entirely on the HID side, which is what this type
/// speaks. Every exchange is a 64 byte report out followed by a 64 byte report in, and up
/// to 60 payload bytes fit in one of them.
///
/// Reports go out with `IOHIDDeviceSetReport` and come back on the interrupt endpoint
/// through an input callback. `IOHIDDeviceGetReport` is not an option: it asks over the
/// control pipe, and this device answers that with a STALL.
///
/// Reference: Microchip DS20005565E, section 3.
@MainActor
final class MCP2221 {

    // MARK: Properties

    /// Microchip's vendor ID.
    nonisolated static let vendorID = 0x04D8

    /// Product ID of the MCP2221 and MCP2221A.
    nonisolated static let productID = 0x00DD

    /// Every report in both directions is this long.
    nonisolated static let reportLength = 64

    /// The largest payload one write or read command can carry.
    nonisolated static let maximumPayload = 60

    /// How long a single report may take to come back.
    private static let replyTimeout = Duration.seconds(2)

    private let handle: HIDHandle

    private var pending: CheckedContinuation<[UInt8], any Error>?

    // MARK: Initialisers

    /// Take the first MCP2221A the system reports, open it and listen for its replies.
    ///
    /// - Throws: ``MCP2221Error/adapterNotFound`` when none is attached,
    ///   ``MCP2221Error/adapterNotOpened(_:)`` when it is there but held elsewhere.
    init() throws {
        guard let device = Self.firstDevice() else {
            throw MCP2221Error.adapterNotFound
        }
        let status = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard status == kIOReturnSuccess else {
            throw MCP2221Error.adapterNotOpened(status)
        }

        handle = HIDHandle(device: device, bufferSize: Self.reportLength)
        IOHIDDeviceRegisterInputReportCallback(
            device,
            handle.buffer,
            CFIndex(Self.reportLength),
            { context, _, _, _, _, bytes, length in
                guard let context else { return }
                let report = Array(UnsafeBufferPointer(start: bytes, count: length))
                let box = Unmanaged<MCP2221>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { box.deliver(report) }
            },
            Unmanaged.passUnretained(self).toOpaque()
        )
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }
}

// MARK: - Bus

extension MCP2221 {

    /// Whether an MCP2221A is attached at all, without opening it.
    nonisolated static func isAttached() -> Bool {
        firstDevice() != nil
    }

    /// Set the bus clock and clear anything the engine was still holding.
    ///
    /// The divider follows the data sheet's own formula, `12 MHz / rate - 2`. The engine
    /// refuses a new speed whilst a transfer is in flight, so this cancels first.
    ///
    /// - Parameter hertz: Bus clock to ask for. The EEPROM handles 400 kHz, and 100 kHz is
    ///   the safe choice over a cable.
    func prepareBus(hertz: Int = 100_000) async throws {
        var command = [UInt8](repeating: 0, count: Self.reportLength)
        command[0] = Command.status
        command[2] = 0x10 // cancel whatever the engine still holds
        command[3] = 0x20 // the next byte is a clock divider
        command[4] = UInt8(max(0, min(255, 12_000_000 / hertz - 2)))
        _ = try await exchange(command, named: .busSetup)
    }

    /// Write bytes to a chip on the bus, address plus payload in one transfer.
    ///
    /// - Parameters:
    ///   - address: Seven-bit address of the chip.
    ///   - payload: What to send after the address. At most ``maximumPayload`` bytes.
    func write(address: UInt8, payload: [UInt8]) async throws {
        precondition(payload.count <= Self.maximumPayload, "payload exceeds one report")

        var command = [UInt8](repeating: 0, count: Self.reportLength)
        command[0] = Command.writeData
        command[1] = UInt8(payload.count & 0xFF)
        command[2] = UInt8(payload.count >> 8)
        command[3] = address << 1
        command.replaceSubrange(4..<(4 + payload.count), with: payload)

        let response = try await exchange(command, named: .write)
        guard response[1] == 0x00 else {
            throw MCP2221Error.engineBusy(command: Operation.write.name)
        }
        try await waitForIdle(address: address)
    }

    /// Read bytes from a chip on the bus.
    ///
    /// - Parameters:
    ///   - address: Seven-bit address of the chip.
    ///   - count: How many bytes to read. At most ``maximumPayload``.
    /// - Returns: Exactly `count` bytes.
    func read(address: UInt8, count: Int) async throws -> [UInt8] {
        precondition(count <= Self.maximumPayload, "read exceeds one report")

        var command = [UInt8](repeating: 0, count: Self.reportLength)
        command[0] = Command.readData
        command[1] = UInt8(count & 0xFF)
        command[2] = UInt8(count >> 8)
        command[3] = (address << 1) | 0x01

        let started = try await exchange(command, named: .read)
        guard started[1] == 0x00 else {
            throw MCP2221Error.engineBusy(command: Operation.read.name)
        }

        var fetch = [UInt8](repeating: 0, count: Self.reportLength)
        fetch[0] = Command.fetchData
        let data = try await exchange(fetch, named: .fetch)
        guard data[1] == 0x00, data[3] != 0x7F else {
            throw MCP2221Error.noAcknowledge(address: address)
        }
        let available = Int(data[3])
        return Array(data[4..<(4 + min(available, count))])
    }
}

// MARK: - Private

private extension MCP2221 {

    enum Command {
        static let status: UInt8 = 0x10
        static let writeData: UInt8 = 0x90
        static let readData: UInt8 = 0x91
        static let fetchData: UInt8 = 0x40
    }

    /// Which step a failure belongs to, so a message can name it in the reader's language.
    enum Operation {
        case busSetup, write, read, fetch, status

        var name: String {
            switch self {
            case .busSetup: return String(localized: "bus setup")
            case .write: return String(localized: "write")
            case .read: return String(localized: "read")
            case .fetch: return String(localized: "fetch")
            case .status: return String(localized: "status")
            }
        }
    }

    nonisolated static func firstDevice() -> IOHIDDevice? {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let criteria: [String: Any] = [
            kIOHIDVendorIDKey: vendorID,
            kIOHIDProductIDKey: productID
        ]
        IOHIDManagerSetDeviceMatching(manager, criteria as CFDictionary)
        let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>
        return devices?.first
    }

    /// Hand a report that has just arrived to whoever is waiting for it.
    func deliver(_ report: [UInt8]) {
        guard let continuation = pending else { return }
        pending = nil
        continuation.resume(returning: report)
    }

    /// Send one report and wait for the answer the device pushes back.
    func exchange(_ command: [UInt8], named operation: Operation) async throws -> [UInt8] {
        let sent = command.withUnsafeBufferPointer { buffer -> IOReturn in
            guard let base = buffer.baseAddress else { return kIOReturnBadArgument }
            return IOHIDDeviceSetReport(
                handle.device,
                kIOHIDReportTypeOutput,
                CFIndex(0),
                base,
                CFIndex(Self.reportLength)
            )
        }
        guard sent == kIOReturnSuccess else {
            throw MCP2221Error.sendFailed(command: operation.name, status: sent)
        }

        let response = try await nextReport(for: operation)
        guard response[0] == command[0] else {
            throw MCP2221Error.unexpectedResponse(command: command[0], received: response[0])
        }
        return response
    }

    /// Wait for the next input report, or give up after ``replyTimeout``.
    func nextReport(for operation: Operation) async throws -> [UInt8] {
        let timeout = Task {
            try await Task.sleep(for: Self.replyTimeout)
            if let waiting = pending {
                pending = nil
                waiting.resume(throwing: MCP2221Error.noReply(command: operation.name))
            }
        }
        defer { timeout.cancel() }

        return try await withCheckedThrowingContinuation { continuation in
            pending = continuation
        }
    }

    /// Poll the engine until it reports itself idle, and check that the chip answered.
    ///
    /// Byte 8 of the status response is zero whilst the engine is idle, and bit 6 of byte
    /// 20 is set when the last address went unacknowledged.
    func waitForIdle(address: UInt8) async throws {
        var status = [UInt8](repeating: 0, count: Self.reportLength)
        status[0] = Command.status

        for _ in 0..<50 {
            let response = try await exchange(status, named: .status)
            if response[20] & 0x40 != 0 {
                throw MCP2221Error.noAcknowledge(address: address)
            }
            if response[8] == 0 {
                return
            }
            try await Task.sleep(for: .milliseconds(1))
        }

        var cancel = [UInt8](repeating: 0, count: Self.reportLength)
        cancel[0] = Command.status
        cancel[2] = 0x10
        _ = try? await exchange(cancel, named: .status)
        throw MCP2221Error.transferTimedOut
    }
}

/// Owns the open device and the buffer its reports land in, and lets go of both together.
///
/// The buffer is allocated rather than taken from an array, because IOKit keeps the
/// pointer for as long as the callback is registered and a Swift array gives no promise
/// about where its storage lives.
private final class HIDHandle: @unchecked Sendable {

    // MARK: Properties

    let device: IOHIDDevice
    let buffer: UnsafeMutablePointer<UInt8>

    private let bufferSize: Int

    // MARK: Initialisers

    init(device: IOHIDDevice, bufferSize: Int) {
        self.device = device
        self.bufferSize = bufferSize
        buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        buffer.initialize(repeating: 0, count: bufferSize)
    }

    deinit {
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        buffer.deinitialize(count: bufferSize)
        buffer.deallocate()
    }
}
