import SwiftUI

/// What a run is doing, and what it left behind.
///
/// The two never appear together, because a run clears the previous result before it
/// starts. The strip takes only the room it needs and the window grows with it, so an idle
/// window carries no reserved gap above its buttons.
struct RunStatusView: View {

    // MARK: Properties

    let activity: ProgrammerModel.Activity
    let result: ProgrammerModel.Result?

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if case let .working(step, fraction) = activity {
                ProgressView(value: fraction) {
                    StepLabelView(step: step)
                }
                .progressViewStyle(.linear)
            }

            if let result {
                ResultView(result: result)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// Names the stretch of work that is running.
private struct StepLabelView: View {

    // MARK: Properties

    let step: ProgrammerModel.Step

    // MARK: Body

    var body: some View {
        switch step {
        case .openingAdapter:
            Label("Opening the adapter", systemImage: "cable.connector")
                .symbolRenderingMode(.hierarchical)
        case .writing:
            Label("Writing", systemImage: "square.and.arrow.up")
                .symbolRenderingMode(.hierarchical)
        case .reading:
            Label("Reading", systemImage: "square.and.arrow.down")
                .symbolRenderingMode(.hierarchical)
        }
    }
}

/// What the last run produced.
private struct ResultView: View {

    // MARK: Properties

    let result: ProgrammerModel.Result

    // MARK: Body

    var body: some View {
        switch result {
        case .written:
            Label(
                "Written and verified. Unplug the adapter and connect the box to its host.",
                systemImage: "checkmark.circle.fill"
            )
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.green)

        case .read:
            Label(
                "Read back. The dump above is what sits on the board.",
                systemImage: "arrow.down.circle.fill"
            )
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.green)

        case let .failed(message):
            Label(message, systemImage: "xmark.octagon.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.red)
        }
    }
}

/// The two things the window can start.
struct ActionBarView: View {

    // MARK: Properties

    let model: ProgrammerModel

    // MARK: Body

    var body: some View {
        HStack {
            Button {
                Task { await model.readBack() }
            } label: {
                Label("Read EEPROM", systemImage: "square.and.arrow.down")
                    .symbolRenderingMode(.hierarchical)
            }
            .disabled(!model.adapterAttached || model.activity != .idle)

            Spacer()

            Button {
                Task { await model.write() }
            } label: {
                Label("Write descriptor", systemImage: "square.and.arrow.up")
                    .symbolRenderingMode(.hierarchical)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canWrite)
        }
    }
}
