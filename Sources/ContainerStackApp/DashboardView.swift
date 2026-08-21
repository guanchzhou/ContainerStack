import ContainerStackCore
import SwiftUI

enum DashboardDestination: String, CaseIterable, Hashable, Identifiable {
    case overview
    case containers
    case images
    case volumes
    case networks
    case stacks

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "Activity Monitor"
        case .containers: "Containers"
        case .images: "Images"
        case .volumes: "Volumes"
        case .networks: "Networks"
        case .stacks: "Stacks"
        }
    }

}

struct DashboardView: View {
    let model: RuntimeViewModel
    // The Activity Monitor is the landing screen now that it shows live per-container
    // resources; previously this defaulted past Overview because Overview said nothing.
    @State private var selection: DashboardDestination = .overview
    @State private var isConfirmingPrune = false
    @State private var searchText = ""
    @State private var focusImagePull = false
    @AppStorage(InspectorPlacement.storageKey) private var inspectorPlacement = InspectorPlacement.trailing.rawValue

    var body: some View {
        NavigationSplitView {
            DashboardSidebar(selection: $selection, model: model)
                .navigationSplitViewColumnWidth(min: 196, ideal: 210, max: 248)
                .navigationTitle("")
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    SidebarRuntimePanel(model: model)
                }
        } detail: {
            NavigationStack {
                Group {
                    switch selection {
                    case .overview:
                        ActivityMonitorView(model: model)
                    case .containers:
                        ContainersView(model: model, searchText: searchText)
                    case .images:
                        ImagesView(
                            model: model,
                            searchText: searchText,
                            focusPull: focusImagePull,
                            onFocusConsumed: { focusImagePull = false }
                        )
                    case .volumes:
                        VolumesView(model: model, searchText: searchText)
                    case .networks:
                        NetworksView(model: model, searchText: searchText)
                    case .stacks:
                        StacksView(model: model, searchText: searchText)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(selection.title)
                .navigationSubtitle(headerSubtitle)
                .searchable(text: $searchText, placement: .toolbar, prompt: "Search")
                .toolbar {
                    ToolbarItem {
                        Button("Run image") {
                            selection = .images
                            focusImagePull = true
                        }
                        .disabled(!model.isHealthy)
                    }
                    ToolbarItem {
                        // Inspector placement: logs and configuration need width, so the
                        // bottom position exists for them. Hidden on the Activity Monitor,
                        // which has no inspector.
                        Picker("Inspector", selection: $inspectorPlacement) {
                            ForEach(InspectorPlacement.allCases) { placement in
                                Image(systemName: placement.symbol)
                                    .help(placement.title)
                                    .accessibilityLabel(placement.title)
                                    .tag(placement.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .help("Move the inspector")
                        .opacity(selection == .overview ? 0 : 1)
                        .disabled(selection == .overview)
                    }
                    ToolbarItem {
                        Menu {
                            Button("Reclaim Space") { isConfirmingPrune = true }
                                .disabled(!model.isHealthy || model.busyResource != nil)
                            Button("Refresh") {
                                Task { await model.refresh() }
                            }
                            .disabled(model.isLoading || model.isStarting)
                        } label: {
                            LucideLabel(title: "More", icon: .ellipsis)
                        }
                    }
                }
            }
        }
        .modifier(AppThemeInjector())
        .confirmationDialog(
            "Remove stopped containers and unused images?",
            isPresented: $isConfirmingPrune,
            titleVisibility: .visible
        ) {
            Button("Reclaim Space", role: .destructive) {
                Task { await model.pruneSystem() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Volumes are not touched. Remove unused volumes from the Volumes screen.")
        }
        .task {
            await model.refresh()
            model.loadStacks()
            await model.refreshStacks()
            await model.adoptDockerContextIfEnabled()
            model.startMonitoring()
        }
        .onDisappear {
            model.stopMonitoring()
        }
        .sheet(isPresented: logsBinding) {
            ContainerLogsSheet(model: model)
        }
        .frame(minWidth: 1040, minHeight: 680)
    }

    private var headerSubtitle: String {
        switch selection {
        case .containers:
            let running = model.containers.filter(\.isRunning).count
            return "\(running) of \(model.containers.count) running"
        case .stacks:
            return "\(model.allStacks.count) stacks"
        case .images:
            return "\(model.images.count) images"
        case .volumes:
            return "\(model.volumes.count) volumes"
        case .networks:
            return "\(model.networks.count) networks"
        case .overview:
            return model.statusTitle
        }
    }

    private var logsBinding: Binding<Bool> {
        Binding(
            get: { model.logs != nil },
            set: { isPresented in
                if !isPresented {
                    model.clearLogs()
                }
            }
        )
    }
}

private struct ContainerLogsSheet: View {
    let model: RuntimeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.logsContainerName.map { "Logs · \($0)" } ?? "Logs")
                    .font(.headline)
                Spacer()
                Button("Close") {
                    model.clearLogs()
                }
                .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                Text(model.logs ?? "")
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(.black.opacity(0.88), in: .rect(cornerRadius: 10))
            .foregroundStyle(.white)
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 460)
    }
}

