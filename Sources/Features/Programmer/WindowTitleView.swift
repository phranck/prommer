import AppKit
import SwiftUI

/// The app's name in capitals between two runs of the LAYERED bars, at the head of the
/// window.
///
/// The window has no title bar, so the name stands in the content. It comes from the
/// bundle, so renaming the app renames the window and nothing has to be kept in step. The
/// bars take whatever the name leaves, which is what centres it, and they sit on the text
/// baseline so that their block and the capitals beside it start and end together.
struct WindowTitleView: View {

    // MARK: Properties

    enum Metrics {
        static let titleSize: CGFloat = 32
        static let spacing: CGFloat = 20
    }

    // MARK: Body

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.spacing) {
            LogoStripesView(fade: .leading)

            Text(Bundle.main.appName.uppercased())
                .font(.custom(BundledFont.title, size: Metrics.titleSize))
                .fixedSize()

            LogoStripesView(fade: .trailing)
        }
        .frame(maxWidth: .infinity)
    }
}

/// The four bars of the LAYERED mark, stacked as the logo stacks them, fading out towards
/// the window edge so that they run off rather than stop.
private struct LogoStripesView: View {

    // MARK: Properties

    /// Everything here comes from the logo, where a bar is a little over three times the gap
    /// below it and the four of them together stand as tall as the capitals of the wordmark.
    /// Reading the cap height from the title face keeps that true when the face changes.
    enum Metrics {
        static let gapRatio: CGFloat = 0.3
        static let fadeLength: CGFloat = 0.45

        static var barCount: Int { Color.layeredStripes.count }

        static var barHeight: CGFloat {
            let capHeight = NSFont(
                name: BundledFont.title,
                size: WindowTitleView.Metrics.titleSize
            )?.capHeight ?? WindowTitleView.Metrics.titleSize
            return capHeight / (CGFloat(barCount) + CGFloat(barCount - 1) * gapRatio)
        }

        static var gap: CGFloat { barHeight * gapRatio }
    }

    /// The side the bars fade out towards, which is the window edge rather than the title.
    let fade: HorizontalEdge

    // MARK: Body

    var body: some View {
        VStack(spacing: Metrics.gap) {
            ForEach(Color.layeredStripes, id: \.self) { stripe in
                stripe.frame(height: Metrics.barHeight)
            }
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: Metrics.fadeLength)
                ],
                startPoint: fade == .leading ? .leading : .trailing,
                endPoint: fade == .leading ? .trailing : .leading
            )
        )
    }
}
