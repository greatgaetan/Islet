import IsletCore
import SwiftUI

/// One task, one decision, then the next.
///
/// A scrollable list of everything left over is a list you skim; a card you have
/// to answer is a decision you actually make. Triage is the ritual — the reading
/// was never the point.
struct RecapCards: View {
    let model: NotchModel
    let isVisible: Bool

    private var recap: RecapModel { model.recap }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let card = recap.current {
                Text(card.task.title)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    // Keyed on the card so each one arrives as a new thing rather
                    // than the previous title mutating into it.
                    .id(card.id)
                    .transition(.opacity)

                Text(subtitle(for: card))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))

                Spacer(minLength: 0)
                actions
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("EVENING REVIEW")
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(.white.opacity(0.35))

            Text("\(recap.index + 1) of \(recap.cards.count)")
                .font(.system(size: 9, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.25))

            Spacer(minLength: 0)

            // Stopping halfway loses nothing: whatever is unanswered rolls to
            // tomorrow. Saying so out loud is what makes it safe to stop.
            NotchGlyph(symbol: "xmark", restOpacity: 0.3) { model.dismissRecap() }
                .frame(width: 22, height: 16)
                .help("Finish later — nothing is lost")
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            PanelButton("Done", emphasis: .primary) { model.answerRecap(.done) }
            PanelButton("Tomorrow") { model.answerRecap(.tomorrow) }
            PanelButton("Defer") { model.answerRecap(.postpone) }
            PanelButton("Delegate") { model.answerRecap(.delegate) }
            PanelButton("Delete", emphasis: .quiet) { model.answerRecap(.delete) }
        }
    }

    private func subtitle(for card: RecapCard) -> String {
        switch card.reason {
        case .completed: "Done today"
        case .open: "Still open"
        case .deferNudge: "Deferred with no date — still worth doing?"
        case .delegateNudge:
            card.task.delegateTo.map { "With \($0) — chase it?" } ?? "Delegated — chase it?"
        }
    }
}
