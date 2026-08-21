import SwiftUI

/// Cards or table, chosen by the user rather than by us.
///
/// The two are good at different things and the right answer depends on the data in front of
/// you: a table compares numbers across many rows, cards read better when there are a
/// handful of items whose identity matters more than their columns. Finder has offered this
/// choice for twenty years; there is no reason to decide it on the user's behalf.
enum ResourceViewMode: String, CaseIterable, Identifiable {
    case cards
    case table

    var id: Self { self }

    var title: String {
        switch self {
        case .cards: "Cards"
        case .table: "Table"
        }
    }

    var symbol: String {
        switch self {
        case .cards: "square.grid.2x2"
        case .table: "tablecells"
        }
    }

    static let storageKey = "resourceViewMode"
}

/// One row shape for every resource screen: an identity, a supporting line, an optional
/// trailing fact, and actions that are visible rather than hidden behind a right-click.
struct ResourceCard<Actions: View>: View {
    let title: String
    var subtitle: String?
    var trailing: String?
    /// nil draws no indicator; the colour carries state, the help text carries it in words.
    var indicator: Color?
    var indicatorHelp: String?
    @ViewBuilder var actions: () -> Actions
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            if let indicator {
                Circle()
                    .fill(indicator)
                    .frame(width: 7, height: 7)
                    .help(indicatorHelp ?? "")
                    .accessibilityLabel(indicatorHelp ?? "")
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            if let trailing {
                Text(trailing)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            // Revealed on hover like Finder's own row controls, but always present for
            // VoiceOver and keyboard users rather than gated on the pointer.
            actions()
                .opacity(isHovered ? 1 : 0.35)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}
