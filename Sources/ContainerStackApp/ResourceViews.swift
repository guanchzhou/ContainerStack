import ContainerStackCore
import SwiftUI

struct VolumesView: View {
    let model: RuntimeViewModel
    var searchText: String = ""
    @State private var isConfirmingPrune = false
    @State private var selectedVolumeName: String?
    @State private var volumeSort = [KeyPathComparator(\DockerVolumeSummary.name)]
    @AppStorage(ResourceViewMode.storageKey) private var viewMode = ResourceViewMode.cards.rawValue
    @State private var pendingVolumeDelete: DockerVolumeSummary?
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ResourceCreateBar(
                placeholder: "Volume name",
                actionTitle: "Create",
                icon: .plus,
                isBusy: model.busyResource != nil,
                isEnabled: model.isHealthy
            ) { name in
                Task { await model.createVolume(named: name) }
            }

            if let error = model.volumesErrorMessage {
                MessageCard(title: error, icon: .triangleAlert, tint: .orange)
                    .padding(.horizontal, 24)
            } else if filteredVolumes.isEmpty {
                EmptyResourceView(
                    title: model.volumes.isEmpty ? "No volumes" : "No matching volumes",
                    description: model.volumes.isEmpty
                        ? "Create a volume above to persist container data between runs."
                        : "Nothing matches “\(searchText)”.",
                    icon: .hardDrive
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ResourceSplitPane {
                    if viewMode == ResourceViewMode.cards.rawValue {
                        List(selection: $selectedVolumeName) {
                            ForEach(filteredVolumes) { volume in
                                ResourceCard(
                                    title: volume.name,
                                    subtitle: volume.mountText,
                                    trailing: volume.driverText
                                ) {
                                    Button {
                                        selectedVolumeName = volume.name
                                        pendingVolumeDelete = volume
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(.red)
                                    .help("Delete volume")
                                    .accessibilityLabel("Delete volume \(volume.name)")
                                    .disabled(model.busyResource != nil || !model.isHealthy)
                                }
                                .tag(volume.name)
                            }
                        }
                        .listStyle(.inset)
                        .contextMenu(forSelectionType: String.self) { selected in
                            if let name = selected.first,
                               let volume = model.volumes.first(where: { $0.name == name }) {
                                Button("Delete Volume…", role: .destructive) {
                                    selectedVolumeName = name
                                    pendingVolumeDelete = volume
                                }
                            }
                        }
                    } else {
                    Table(filteredVolumes, selection: $selectedVolumeName, sortOrder: $volumeSort) {
                        TableColumn("Name", value: \.name) { volume in
                            Text(volume.name).fontWeight(.medium)
                        }
                        .width(min: 140, ideal: 220)
                        TableColumn("Driver", value: \.driverText) { volume in
                            Text(volume.driverText).foregroundStyle(.secondary)
                        }
                        .width(min: 60, ideal: 90)
                        TableColumn("Mount point", value: \.mountText) { volume in
                            Text(volume.mountText)
                                .foregroundStyle(.secondary)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                        .width(min: 160, ideal: 320)
                    }
                    .tableStyle(.inset(alternatesRowBackgrounds: false))
                    // Right-click actions: a native affordance the hand-rolled rows never had.
                    .contextMenu(forSelectionType: String.self) { selected in
                        if let name = selected.first,
                           let volume = model.volumes.first(where: { $0.name == name }) {
                            Button("Delete Volume…", role: .destructive) {
                                selectedVolumeName = name
                                pendingVolumeDelete = volume
                            }
                        }
                    }
                    }
                } inspector: {
                    VolumeInspector(volume: selectedVolume, model: model)
                }
                .confirmationDialog(
                    "Delete volume \(pendingVolumeDelete?.name ?? "")?",
                    isPresented: Binding(
                        get: { pendingVolumeDelete != nil },
                        set: { if !$0 { pendingVolumeDelete = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Delete Volume", role: .destructive) {
                        if let volume = pendingVolumeDelete {
                            Task { await model.remove(volume: volume) }
                        }
                        pendingVolumeDelete = nil
                    }
                    Button("Cancel", role: .cancel) { pendingVolumeDelete = nil }
                } message: {
                    Text("Volume data is deleted permanently and cannot be restored.")
                }
            }

            ResourceStatus(model: model)
        }
        .background(theme.windowBackground)
        .toolbar {
            ToolbarItem {
                Button {
                    isConfirmingPrune = true
                } label: {
                    LucideLabel(title: "Remove Unused", icon: .trash)
                }
                .disabled(!model.isHealthy || model.busyResource != nil || model.volumes.isEmpty)
            }
        }
        .confirmationDialog(
            "Remove volumes that no container uses?",
            isPresented: $isConfirmingPrune,
            titleVisibility: .visible
        ) {
            Button("Remove Unused Volumes", role: .destructive) {
                Task { await model.pruneUnusedVolumes() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Volume data is deleted permanently and cannot be restored.")
        }
    }

    private var filteredVolumes: [DockerVolumeSummary] {
        model.volumes.filter { volume in
            ResourceSearch.matches(searchText, volume.name, volume.mountpoint, volume.driver)
        }
    }

    private var selectedVolume: DockerVolumeSummary? {
        guard let selectedVolumeName else { return nil }
        return model.volumes.first { $0.name == selectedVolumeName }
    }
}

struct NetworksView: View {
    let model: RuntimeViewModel
    var searchText: String = ""
    @State private var selectedNetworkID: String?
    @State private var networkSort = [KeyPathComparator(\DockerNetworkSummary.name)]
    @AppStorage(ResourceViewMode.storageKey) private var viewMode = ResourceViewMode.cards.rawValue
    @State private var pendingNetworkDelete: DockerNetworkSummary?
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ResourceCreateBar(
                placeholder: "Network name",
                actionTitle: "Create",
                icon: .plus,
                isBusy: model.busyResource != nil,
                isEnabled: model.isHealthy
            ) { name in
                Task { await model.createNetwork(named: name) }
            }

            if let error = model.networksErrorMessage {
                MessageCard(title: error, icon: .triangleAlert, tint: .orange)
                    .padding(.horizontal, 24)
            } else if filteredNetworks.isEmpty {
                EmptyResourceView(
                    title: model.networks.isEmpty ? "No networks" : "No matching networks",
                    description: model.networks.isEmpty
                        ? "Create a network above to give containers their own subnet."
                        : "Nothing matches “\(searchText)”.",
                    icon: .network
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ResourceSplitPane {
                    if viewMode == ResourceViewMode.cards.rawValue {
                        List(selection: $selectedNetworkID) {
                            ForEach(filteredNetworks) { network in
                                ResourceCard(
                                    title: network.name,
                                    subtitle: network.subnetText == "—"
                                        ? network.driverText
                                        : "\(network.subnetText) · gateway \(network.gatewayText)",
                                    trailing: network.driverText
                                ) {
                                    Button {
                                        selectedNetworkID = network.id
                                        pendingNetworkDelete = network
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(.red)
                                    .help("Delete network")
                                    .accessibilityLabel("Delete network \(network.name)")
                                    .disabled(model.busyResource != nil || !model.isHealthy)
                                }
                                .tag(network.id)
                            }
                        }
                        .listStyle(.inset)
                        .contextMenu(forSelectionType: String.self) { selected in
                            if let id = selected.first,
                               let network = model.networks.first(where: { $0.id == id }) {
                                Button("Delete Network…", role: .destructive) {
                                    selectedNetworkID = id
                                    pendingNetworkDelete = network
                                }
                            }
                        }
                    } else {
                    Table(filteredNetworks, selection: $selectedNetworkID, sortOrder: $networkSort) {
                        TableColumn("Name", value: \.name) { network in
                            Text(network.name).fontWeight(.medium)
                        }
                        .width(min: 130, ideal: 200)
                        TableColumn("Driver", value: \.driverText) { network in
                            Text(network.driverText).foregroundStyle(.secondary)
                        }
                        .width(min: 60, ideal: 80)
                        TableColumn("Subnet", value: \.subnetText) { network in
                            Text(network.subnetText).foregroundStyle(.secondary).monospaced()
                        }
                        .width(min: 110, ideal: 160)
                        TableColumn("Gateway", value: \.gatewayText) { network in
                            Text(network.gatewayText).foregroundStyle(.secondary).monospaced()
                        }
                        .width(min: 110, ideal: 160)
                    }
                    .tableStyle(.inset(alternatesRowBackgrounds: false))
                    .contextMenu(forSelectionType: String.self) { selected in
                        if let id = selected.first,
                           let network = model.networks.first(where: { $0.id == id }) {
                            Button("Delete Network…", role: .destructive) {
                                selectedNetworkID = id
                                pendingNetworkDelete = network
                            }
                        }
                    }
                    }
                } inspector: {
                    NetworkInspector(network: selectedNetwork, model: model)
                }
                .confirmationDialog(
                    "Delete network \(pendingNetworkDelete?.name ?? "")?",
                    isPresented: Binding(
                        get: { pendingNetworkDelete != nil },
                        set: { if !$0 { pendingNetworkDelete = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Delete Network", role: .destructive) {
                        if let network = pendingNetworkDelete {
                            Task { await model.remove(network: network) }
                        }
                        pendingNetworkDelete = nil
                    }
                    Button("Cancel", role: .cancel) { pendingNetworkDelete = nil }
                } message: {
                    Text("Containers attached to this network lose it until they are recreated.")
                }
            }

            ResourceStatus(model: model)
        }
        .background(theme.windowBackground)
    }

    private var filteredNetworks: [DockerNetworkSummary] {
        model.networks.filter { network in
            ResourceSearch.matches(searchText, network.name, network.subnet, network.driver)
        }
    }

    private var selectedNetwork: DockerNetworkSummary? {
        guard let selectedNetworkID else { return nil }
        return model.networks.first { $0.id == selectedNetworkID }
    }
}

private struct VolumeInspector: View {
    let volume: DockerVolumeSummary?
    let model: RuntimeViewModel

    var body: some View {
        if let volume {
            VStack(alignment: .leading, spacing: 0) {
                InspectorHeader(
                    title: volume.name,
                    subtitle: volume.mountpoint ?? "No mountpoint"
                ) {
                    InspectorAction(title: "Delete", destructive: true) {
                        Task { await model.remove(volume: volume) }
                    }
                }
                .disabled(model.busyResource != nil || !model.isHealthy)

                InspectorStatBlock(
                    rows: [
                        ("Driver", volume.driver ?? "local", false),
                        ("Mount", volume.mountpoint ?? "—", true),
                        ("Created", volume.createdAt ?? "—", false),
                        ("Used by", "—", false),
                    ]
                )
            }
        } else {
            EmptyInspector()
        }
    }
}

private struct NetworkInspector: View {
    let network: DockerNetworkSummary?
    let model: RuntimeViewModel

    var body: some View {
        if let network {
            let attached = ResourceUsage.containers(onNetwork: network.name, from: model.containers)
            VStack(alignment: .leading, spacing: 0) {
                InspectorHeader(
                    title: network.name,
                    subtitle: network.subnet ?? "No subnet",
                    pill: network.driver
                ) {
                    InspectorAction(title: "Delete", destructive: true) {
                        Task { await model.remove(network: network) }
                    }
                }
                .disabled(model.busyResource != nil || !model.isHealthy)

                InspectorStatBlock(
                    rows: [
                        ("Driver", network.driver ?? "nat", false),
                        ("Subnet", network.subnet ?? "—", true),
                        ("Gateway", network.gateway ?? "—", true),
                        (
                            "Attached",
                            attached.isEmpty ? "—" : attached.map(\.name).joined(separator: ", "),
                            false
                        ),
                    ]
                )
            }
        } else {
            EmptyInspector()
        }
    }
}

private struct ResourceStatus: View {
    let model: RuntimeViewModel

    var body: some View {
        if let resourceMessage = model.resourceMessage {
            MessageCard(title: resourceMessage, icon: .info, tint: .secondary)
                .padding(.horizontal, 24)
                .padding(.top, 8)
        }
    }
}
