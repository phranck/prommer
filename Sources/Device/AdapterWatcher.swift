import Foundation
import IOKit
import IOKit.hid
import Observation

/// Reports whether an MCP2221A is plugged in, and keeps reporting it.
///
/// IOKit tells us about arrivals and departures through two callbacks on the run loop,
/// so the window never has to ask. The first state comes from a one-off scan at start,
/// because the matching callback only fires for devices that appear afterwards.
@MainActor
@Observable
final class AdapterWatcher {

    // MARK: Properties

    /// Whether an adapter is attached right now.
    private(set) var isAttached = false

    @ObservationIgnored
    private var registration: Registration?

    // MARK: Initialisers

    init() {}
}

// MARK: - Lifecycle

extension AdapterWatcher {

    /// Begin watching. Calling this twice does nothing the second time.
    func start() {
        guard registration == nil else { return }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let criteria: [String: Any] = [
            kIOHIDVendorIDKey: MCP2221.vendorID,
            kIOHIDProductIDKey: MCP2221.productID
        ]
        IOHIDManagerSetDeviceMatching(manager, criteria as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, adapterArrivedOrLeft, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, adapterArrivedOrLeft, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        registration = Registration(manager: manager)
        isAttached = MCP2221.isAttached()
    }

    /// Stop watching and let go of the manager.
    func stop() {
        registration = nil
    }

    /// Re-read the current state. The callbacks fire slightly before IOKit's device list
    /// settles, so a removal is confirmed by scanning rather than by counting events.
    fileprivate func deviceSetChanged() {
        isAttached = MCP2221.isAttached()
    }
}

// MARK: - Private

/// Owns the manager and unwinds it when the watcher goes away.
///
/// A `@MainActor` type's `deinit` runs outside that isolation and may not touch a value
/// IOKit leaves unannotated, so the teardown lives here instead.
private final class Registration: @unchecked Sendable {

    // MARK: Properties

    private let manager: IOHIDManager

    // MARK: Initialisers

    init(manager: IOHIDManager) {
        self.manager = manager
    }

    deinit {
        IOHIDManagerUnscheduleFromRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.defaultMode.rawValue
        )
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }
}

/// Both IOKit callbacks land here. They carry the watcher as an opaque context, because
/// a C function pointer cannot capture anything.
private func adapterArrivedOrLeft(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context else { return }
    let watcher = Unmanaged<AdapterWatcher>.fromOpaque(context).takeUnretainedValue()
    Task { @MainActor in
        watcher.deviceSetChanged()
    }
}
