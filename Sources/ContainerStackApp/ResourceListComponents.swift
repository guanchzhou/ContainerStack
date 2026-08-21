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
    @ViewBuilder var list: () -> ListContent
    @ViewBuilder var inspector: () -> Inspector
    @AppStorage(InspectorPlacement.storageKey) private var placementRaw = InspectorPlacement.trailing.rawValue

    private var placement: InspectorPlacement {
        InspectorPlacement(rawValue: placementRaw) ?? .trailing
    }

    var body: some View {
        // H/VSplitView rather than a fixed frame: the divider becomes draggable, so the
        // inspector is no longer locked to one width the user cannot change.
        switch placement {
        case .trailing:
            HSplitView {
                list().frame(minWidth: 340)
                inspector().frame(minWidth: 300, idealWidth: 404)
            }
        case .bottom:
            VSplitView {
                list().frame(minHeight: 140)
                inspector().frame(minHeight: 200, idealHeight: 340)
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
            VStack(spacing: 0) {
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
