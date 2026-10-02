import SwiftUI

/// The window's background: the retro artwork, blurred, over the material that samples what
/// lies behind the window.
///
/// The artwork is `Artwork/WindowBackdrop.svg`, built from the four bars of the LAYERED mark
/// so that the window and the title are coloured out of the same palette.
///
/// The two cannot be one thing. A material blends against the desktop behind the window and
/// an image is inside it, so the only way to have both is to stack them and let the image
/// be partly transparent. How much of the desktop still shows through is therefore what
/// ``Metrics/artworkOpacity`` decides.
struct WindowBackdropView: View {

    // MARK: Properties

    enum Metrics {
        /// Far enough that the stripes soften into bands, close enough that they still read
        /// as stripes.
        static let blur: CGFloat = 21

        /// How much of the artwork stands in front of the material.
        static let artworkOpacity: Double = 0.28

        /// What the artwork is multiplied by, so its colours darken without going flat.
        ///
        /// Two values, because the cards and the text have to stay readable on it. A light
        /// window sets near-black text on a card that is barely darker than its surround,
        /// and taking the artwork down as far as the dark window needs would leave both
        /// unreadable.
        static func darkening(for scheme: ColorScheme) -> Color {
            Color(white: scheme == .dark ? 0.35 : 0.8)
        }
    }

    @Environment(\.colorScheme) private var colorScheme

    // MARK: Body

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)

            Image(.windowBackdrop)
                .resizable()
                .scaledToFill()
                // An opaque blur, because the ordinary one lets the edges of the image fade
                // into nothing and those edges are the window's own edges.
                .blur(radius: Metrics.blur, opaque: true)
                .colorMultiply(Metrics.darkening(for: colorScheme))
                .opacity(Metrics.artworkOpacity)
        }
    }
}
