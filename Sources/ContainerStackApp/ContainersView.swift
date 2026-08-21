import ContainerStackCore
import SwiftUI

struct ContainersView: View {
    let model: RuntimeViewModel
    var searchText: String = ""
    @Environment(\.appTheme) private var theme
    @State private var inspectorTab = ContainerInspector.Tab.stats
    @State private var sort = [KeyPathComparator(\DockerContainerSummary.name)]
    @State private var pendingDelete: DockerContainerSummary?
    @AppStorage(ResourceViewMode.storageKey) private var viewMode = ResourceViewMode.cards.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error = model.containersErrorMessage {
                MessageCard(title: error, icon: .triangleAlert, tint: .orange)
                    .padding(24)
            } else if filteredGroups.isEmpty {
                EmptyResourceView(
                    title: model.containers.isEmpty ? "No containers" : "No matching containers",
                    description: model.containers.isEmpty
                        ? "Run an image to see its container here. "
                            + "Stopped containers stay visible so you can restart or remove them."
                        : "Nothing matches “\(searchText)”.",
                    icon: .container
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ResourceSplitPane(hasSelection: selectedContainer != nil) {
                    Group {
                    if viewMode == ResourceViewMode.cards.rawValue {
                        // Sections restore the Compose grouping the table could only express
                        // as a sortable column.
                        List(selection: containerSelection) {
                            ForEach(filteredGroups) { group in
                                Section(group.project ?? "Not in a stack") {
                                    ForEach(group.containers) { container in
                                        ContainerCardRow(
                                            container: container,
                                            model: model,
                                            onShowLogs: {
                                                model.selectedContainerID = container.id
                                                inspectorTab = .logs
                                            },
                                            onDelete: {
                                                model.selectedContainerID = container.id
                                                pendingDelete = container
                                            }
                                        )
                                        .tag(container.id)
                                    }
                                }
                            }
                        }
                        .listStyle(.inset)
                    } else {
                    Table(flatContainers, selection: containerSelection, sortOrder: $sort) {
                        TableColumn("Name", value: \.name) { container in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(container.isRunning ? Color.green : Color.secondary)
                                    .frame(width: 6, height: 6)
                                    .accessibilityHidden(true)
                                Text(container.name).fontWeight(.medium)
                            }
                        }
                        .width(min: 130, ideal: 200)
                        TableColumn("Image", value: \.imageText) { container in
                            Text(container.imageText)
                                .foregroundStyle(.secondary)
                                .truncationMode(.middle)
                        }
                        .width(min: 150, ideal: 260)
                        TableColumn("State", value: \.stateText) { container in
                            Text(container.stateText)
                                .foregroundStyle(container.isRunning ? .primary : .secondary)
                        }
                        .width(min: 90, ideal: 130)
                        // Replaces the old collapsible group headers: sorting by this column
                        // groups a stack together and is sortable the other way too.
                        TableColumn("Stack", value: \.stackText) { container in
                            Text(container.stackText).foregroundStyle(.secondary)
                        }
                        .width(min: 80, ideal: 120)
                        TableColumn("Ports", value: \.portsText) { container in
                            Text(container.portsText)
                                .foregroundStyle(.secondary)
                                .monospaced()
                                .textSelection(.enabled)
                        }
                        .width(min: 110, ideal: 170)
                    }
                    .tableStyle(.inset(alternatesRowBackgrounds: false))
                    }
                    }
                    .contextMenu(forSelectionType: String.self) { selected in
                        if let id = selected.first,
                           let container = model.containers.first(where: { $0.id == id }) {
                            Button(container.isRunning ? "Stop" : "Start") {
                                Task { await model.toggle(container: container) }
                            }
                            Button("Restart") {
                                Task { await model.restart(container: container) }
                            }
                            Button("Show Logs") {
                                model.selectedContainerID = id
                                inspectorTab = .logs
                            }
                            Divider()
                            Button("Delete Container…", role: .destructive) {
                                model.selectedContainerID = id
                                pendingDelete = container
                            }
                        }
                    }
                } inspector: {
                    ContainerInspector(
                        container: selectedContainer,
                        model: model,
                        tab: $inspectorTab
                    )
                }
                .confirmationDialog(
                    "Delete container \(pendingDelete?.name ?? "")?",
                    isPresented: Binding(
                        get: { pendingDelete != nil },
                        set: { if !$0 { pendingDelete = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Delete Container", role: .destructive) {
                        if let container = pendingDelete {
                            Task { await model.remove(container: container) }
                        }
                        pendingDelete = nil
                    }
                    Button("Cancel", role: .cancel) { pendingDelete = nil }
                } message: {
                    Text("The container and its writable layer are deleted. Named volumes are kept.")
                }
            }

            if let containerMessage = model.containerMessage {
                MessageCard(title: containerMessage, icon: .info, tint: .secondary)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }
        }
        .background(theme.windowBackground)
    }

    private var filteredGroups: [ContainerGroup] {
        ResourceSearch.containerGroups(model.containerGroups, query: searchText)
    }

    /// Table is flat, so the Compose grouping becomes a sortable column instead of
    /// collapsible headers.
    private var flatContainers: [DockerContainerSummary] {
        filteredGroups.flatMap(\.containers).sorted(using: sort)
    }

    /// The selected id lives on the view model, so Table binds through it rather than
    /// keeping a second copy that could disagree.
    private var containerSelection: Binding<String?> {
        Binding(
            get: { model.selectedContainerID },
            set: { model.selectedContainerID = $0 }
        )
    }

    private var selectedContainer: DockerContainerSummary? {
        guard let selectedContainerID = model.selectedContainerID else { return nil }
        return model.containers.first { $0.id == selectedContainerID }
    }

}



/// The container card: state at a glance, the two actions people reach for most, and delete
/// separated from them. Extracted to keep the type checker inside its budget.
private struct ContainerCardRow: View {
    let container: DockerContainerSummary
    let model: RuntimeViewModel
    let onShowLogs: () -> Void
    let onDelete: () -> Void

    private var subtitle: String {
        let image = container.imageText
        guard let ports = container.portSummary else { return image }
        return "\(image) · \(ports)"
    }

    var body: some View {
        ResourceCard(
            title: container.name,
            subtitle: subtitle,
            trailing: container.stateText,
            indicator: container.isRunning ? .green : .secondary,
            indicatorHelp: container.isRunning ? "Running" : "Not running"
        ) {
            Button {
                Task { await model.toggle(container: container) }
            } label: {
                Image(systemName: container.isRunning ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.borderless)
            .help(container.isRunning ? "Stop" : "Start")
            .accessibilityLabel(container.isRunning ? "Stop \(container.name)" : "Start \(container.name)")

            Button(action: onShowLogs) {
                Image(systemName: "text.alignleft")
            }
            .buttonStyle(.borderless)
            .help("Logs")
            .accessibilityLabel("Logs for \(container.name)")

            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .help("Delete")
            .accessibilityLabel("Delete \(container.name)")
        }
        .disabled(model.busyContainerID != nil || !model.isHealthy)
    }
}
