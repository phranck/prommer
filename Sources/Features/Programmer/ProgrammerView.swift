import SwiftUI

/// The single window: what will be written, what the adapter is doing, what came back.
struct ProgrammerView: View {

    // MARK: Properties

    /// The window does not resize, so every width in it is known in advance. That matters
    /// for the hex dump, whose point size is derived from the room it has: measuring that
    /// room instead would feed the text's own width back into the measurement.
    ///
    /// The height is not among these numbers and the top padding is not either. The height
    /// follows from what the window holds, and the room above the title is the safe area the
    /// hidden title bar leaves, which is what keeps the title clear of the window buttons.
    enum Layout {
        static let windowWidth: CGFloat = 780
        static let windowPadding: CGFloat = 24
        static let panelPadding: CGFloat = 16

        /// What a panel offers its content.
        static var panelContentWidth: CGFloat {
            windowWidth - 2 * windowPadding - 2 * panelPadding
        }
    }

    @Bindable var model: ProgrammerModel

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            WindowTitleView()

            AdapterStatusView(attached: model.adapterAttached)

            DescriptorFormView(
                descriptor: $model.descriptor,
                serialNumber: $model.serialNumber
            )

            PayloadView(image: model.image, identity: model.identity)

            if model.activity != .idle || model.lastResult != nil {
                RunStatusView(activity: model.activity, result: model.lastResult)
            }

            ActionBarView(model: model)
        }
        .padding(.horizontal, Layout.windowPadding)
        .padding(.bottom, Layout.windowPadding)
        .frame(width: Layout.windowWidth, alignment: .topLeading)
        .containerBackground(for: .window) { WindowBackdropView() }
        .task { model.startWatchingAdapter() }
        .task(id: model.adapterAttached) {
            if model.adapterAttached {
                await model.inspectChip()
            } else {
                model.forgetChip()
            }
        }
    }
}

/// Says whether the programming adapter is plugged in.
///
/// IOKit reports arrivals and departures, so this follows the cable without anybody
/// pressing anything.
private struct AdapterStatusView: View {

    // MARK: Properties

    let attached: Bool

    // MARK: Body

    var body: some View {
        HStack(spacing: 10) {
            // The same symbol in both states. The color says whether something is plugged in,
            // and a second symbol beside it would say that twice.
            Image(systemName: "cable.connector")
                .font(.system(size: 30))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(attached ? Color.green : Color.secondary)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(attached ? "MCP2221A connected" : "No adapter")
                    .font(.headline)
                Text(attached
                     ? "Connect J1 on the board and leave its USB socket empty."
                     : "Plug the Adafruit MCP2221A breakout into this Mac.")
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.default, value: attached)
    }
}

#Preview {
    ProgrammerView(model: ProgrammerModel())
}
