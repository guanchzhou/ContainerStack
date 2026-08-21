import ContainerStackCore
import SwiftUI

/// Where the detail pane sits. Logs and configuration are wide, not tall, so a 404pt
/// column wraps every line; at the bottom they get the window's full width.
enum InspectorPlacement: String, CaseIterable, Identifiable {
    case trailing
    case bottom

    var id: Self { self }

    var title: String {
        switch self {
        case .trailing: "Inspector on Right"
        case .bottom: "Inspector at Bottom"
        }
    }

    var symbol: String {
        switch self {
        case .trailing: "square.righthalf.filled"
        case .bottom: "square.bottomhalf.filled"
        }
    }

    static let storageKey = "inspectorPlacement"
}

struct ResourceSplitPane<ListContent: View, Inspector: View>: View {
    /// Nothing selected means nothing to inspect, so the pane is not drawn at all. It used
    /// to hold roughly 60% of the window to say "No Selection".
    var hasSelection: Bool
    @ViewBuilder var list: () -> ListContent
    @ViewBuilder var inspector: () -> Inspector
    @AppStorage(InspectorPlacement.storageKey) private var placementRaw = InspectorPlacement.trailing.rawValue

    private var placement: InspectorPlacement {
        InspectorPlacement(rawValue: placementRaw) ?? .trailing
    }

    var body: some View {
        // H/VSplitView rather than a fixed frame: the divider becomes draggable, so the
        // inspector is no longer locked to one width the user cannot change.
        if !hasSelection {
            list()
        } else {
            switch placement {
            case .trailing:
                HSplitView {
                    list().frame(minWidth: 340, maxWidth: .infinity)
                    // maxWidth matters: without it the inspector's own content decides how
                    // much it takes — the segmented Stats/Logs/Ports picker asks for width
                    // proportional to its labels — so the list column jumped every time the
                    // selection changed.
                    inspector().frame(minWidth: 300, idealWidth: 404, maxWidth: 460)
                }
            case .bottom:
                VSplitView {
                    // The list yields space here: it scrolls, the inspector clips. Before
                    // this the inspector got ~180pt and ran under the window edge.
                    list().frame(minHeight: 120, idealHeight: 220)
                    inspector().frame(minHeight: 300)
                }
            }
        }
    }
}

struct EmptyInspector: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        Text("No Selection")
            .font(.system(size: 13))
            .foregroundStyle(theme.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.windowBackground)
    }
}

struct InspectorHeader<Actions: View>: View {
    let title: String
    let subtitle: String
    var pill: String? = nil
    @ViewBuilder var actions: () -> Actions
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                if let pill {
                    Text(pill)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Color.white.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                        )
                }
            }
            Text(subtitle)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.top, 5)
            HStack(spacing: 6) {
                actions()
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 16)
        .padding(.top, 15)
        .padding(.bottom, 8)
    }
}

struct InspectorStatBlock: View {
    let rows: [(key: String, value: String, mono: Bool)]
    @Environment(\.appTheme) private var theme

    var body: some View {
        ScrollView {
            // Adapts to the pane's shape rather than assuming a narrow column: at the
            // bottom placement there is width for several facts per line, and a single tall
            // column there would need scrolling for content that fits.
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 260), spacing: 0)],
                spacing: 0
            ) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(row.key)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textSecondary)
                            .frame(width: 96, alignment: .leading)
                        Text(row.value)
                            .font(row.mono ? .system(size: 12, design: .monospaced) : .system(size: 12))
                            .foregroundStyle(theme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(theme.hairline).frame(height: 0.5)
                    }
                }
            }
            .background(theme.sidebarBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(theme.hairline, lineWidth: 0.5)
            )
            .padding(16)
        }
        .background(theme.windowBackground)
    }
}

struct InspectorAction: View {
    let title: String
    var prominent: Bool = false
    var destructive: Bool = false
    let action: () -> Void
    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(destructive ? theme.destructive : Color.white)
                .padding(.horizontal, 12)
                .frame(height: 22)
                .background(
                    prominent ? theme.accent : theme.sidebarBackground,
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(theme.hairline, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}

enum ResourceUsage {
    static func containers(
        usingImage image: DockerImageSummary,
        from containers: [DockerContainerSummary]
    ) -> [DockerContainerSummary] {
        let tags = Set(image.repositoryTags ?? [])
        let digest = normalizedDigest(image.id)
        return containers.filter { container in
            if let imageID = container.imageID, !imageID.isEmpty {
                let candidate = normalizedDigest(imageID)
                return candidate == digest || (candidate.count == 12 && digest.hasPrefix(candidate))
            }
            if let name = container.image {
                return tags.contains(name) || normalizedDigest(name) == digest
            }
            return false
        }
    }

    private static func normalizedDigest(_ identifier: String) -> String {
        identifier.hasPrefix("sha256:")
            ? String(identifier.dropFirst("sha256:".count))
            : identifier
    }

    static func containers(
        onNetwork name: String,
        from containers: [DockerContainerSummary]
    ) -> [DockerContainerSummary] {
        containers.filter { $0.networkNames.contains(name) }
    }
}
