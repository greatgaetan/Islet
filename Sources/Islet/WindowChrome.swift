import SwiftUI

/// The window half of Islet, dressed like the island half.
///
/// They used to be two different apps to look at. The island is black at every
/// hour; the windows were a stock `Form`, which follows the system appearance
/// and renders *light* half the time, with system-blue controls. Nothing was
/// broken and nothing matched.
///
/// Everything here is borrowed rather than invented: the island's black, its
/// 9 pt tracked section headers, its white opacities, its spacing steps. A
/// window should look like a piece of the island that came away.
enum WindowStyle {
    static let background = Color.black
    static let group = Color.white.opacity(0.05)
    static let separator = Color.white.opacity(0.07)
    static let header = Color.white.opacity(0.35)
    static let label = Color.white.opacity(0.9)
    static let secondary = Color.white.opacity(0.55)
    static let footnote = Color.white.opacity(0.3)

    /// Between the island's 16 and its 26: a card inside a window, not the
    /// silhouette itself.
    static let groupRadius: CGFloat = 14

    /// The pale azure the app already uses, and not white.
    ///
    /// White was the first answer and it failed the only test that matters for a
    /// switch: on a black window a white track under a white knob reads as *off*.
    /// State legibility beats palette purity, and it beats it hardest for a
    /// colour-blind reader.
    ///
    /// A sixth hue was the alternative and it is not needed. A switch has to be
    /// told from its own off state — a lightness job — not from three category
    /// marks, so reusing the brightest colour in the palette costs nothing and
    /// makes the windows look like the island rather than like macOS.
    static let accent = Color(red: 0.62, green: 0.88, blue: 0.98)

    enum Spacing {
        static let betweenSections: CGFloat = 22
        static let afterHeader: CGFloat = 10
        static let beforeFootnote: CGFloat = 8
        static let windowPadding: CGFloat = 20
    }
}

/// A titled group of rows, with the explanation underneath where the island
/// puts it — prose beats an ⓘ you have to go and find.
struct IsletSection<Content: View>: View {
    let title: String
    var footnote: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(WindowStyle.header)

            Spacer(minLength: 0).frame(height: WindowStyle.Spacing.afterHeader)

            VStack(spacing: 0) { content }
                .background(
                    RoundedRectangle(cornerRadius: WindowStyle.groupRadius, style: .continuous)
                        .fill(WindowStyle.group)
                )

            if let footnote {
                Spacer(minLength: 0).frame(height: WindowStyle.Spacing.beforeFootnote)
                Text(footnote)
                    .font(.system(size: 11))
                    .foregroundStyle(WindowStyle.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One line: a label, and whatever sets it on the right.
///
/// The height is fixed rather than derived, for the same reason the task rows
/// are: a row that measures its contents changes height when a control appears,
/// and a list that twitches is worse than a list that is a pixel off.
struct IsletRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(WindowStyle.label)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(WindowStyle.footnote)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 14)
        .frame(height: subtitle == nil ? 40 : 52)
    }
}

/// Inset to the label, so the rows read as one card rather than a stack of them.
struct IsletDivider: View {
    var inset: CGFloat = 14

    var body: some View {
        Rectangle()
            .fill(WindowStyle.separator)
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

/// The value beside a control — always monospaced, so a stepper held down does
/// not shuffle the label next to it.
struct IsletValue: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .monospacedDigit()
            .foregroundStyle(WindowStyle.secondary)
    }
}

/// The strip along the bottom. Ambient, never a control: what the app is holding
/// right now, and which build is holding it.
struct IsletStatusBar: View {
    let leading: String
    let trailing: String

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(WindowStyle.separator).frame(height: 1)
            HStack(spacing: 8) {
                Text(leading)
                Spacer(minLength: 0)
                Text(trailing)
            }
            .font(.system(size: 11))
            .foregroundStyle(WindowStyle.footnote)
            .padding(.horizontal, WindowStyle.Spacing.windowPadding)
            .frame(height: 30)
        }
        .background(WindowStyle.background)
    }
}

extension Bundle {
    /// "1.0" when there is a bundle, "from source" when Islet is being run
    /// straight out of the build directory — which is a fact worth showing
    /// rather than a blank.
    var isletVersion: String {
        guard let short = infoDictionary?["CFBundleShortVersionString"] as? String else {
            return "from source"
        }
        return "v\(short)"
    }
}

extension View {
    /// A switch, tinted white.
    ///
    /// Outside a `Form`, macOS renders a bare `Toggle` as a *checkbox* — and a
    /// blue one, borrowing the system accent that nothing else here uses. Both
    /// have to be said out loud.
    func isletSwitch() -> some View {
        labelsHidden()
            .toggleStyle(.switch)
            .tint(WindowStyle.accent)
    }
}
