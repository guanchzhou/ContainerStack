import AppKit
import ContainerStackCore
import SwiftUI
import UniformTypeIdentifiers

struct StacksView: View {
    let model: RuntimeViewModel
    var searchText: String = ""

    @State private var showingNewStack = false
    @State private var newStackName = ""
    @State private var newStackDirectory: URL?
    @State private var selectedStackID: UUID?
    @State private var stackSort = [KeyPathComparator(\ComposeStack.name)]
    @AppStorage(ResourceViewMode.storageKey) private var viewMode = ResourceViewMode.cards.rawValue
    @State private var openedStackID: UUID?
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error = model.stacksErrorMessage {
                MessageCard(title: error, icon: .triangleAlert, tint: .orange)
                    .padding(24)
            } else if filteredStacks.isEmpty {
                EmptyResourceView(
                    title: model.allStacks.isEmpty ? "No stacks" : "No matching stacks",
                    description: model.allStacks.isEmpty
                        ? "A stack is a Docker Compose project you can run and edit from "
                            + "here. Add an existing compose file or start a new one."
                        : "Nothing matches “\(searchText)”.",
                    icon: .layers
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ResourceSplitPane {
                    Group {
                    if viewMode == ResourceViewMode.cards.rawValue {
                        List(selection: $selectedStackID) {
                            ForEach(filteredStacks) { stack in
                                ResourceCard(title: stack.name, subtitle: stack.filePathText) {
                                    EmptyView()
                                }
                                .tag(stack.id)
                            }
                        }
                        .listStyle(.inset)
                    } else {
                    Table(filteredStacks, selection: $selectedStackID, sortOrder: $stackSort) {
                        TableColumn("Stack", value: \.name) { stack in
                            Text(stack.name).fontWeight(.medium)
                        }
                        .width(min: 120, ideal: 180)
                        TableColumn("Compose file", value: \.filePathText) { stack in
                            Text(stack.filePathText)
                                .foregroundStyle(.secondary)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                        .width(min: 200, ideal: 380)
                    }
                    .tableStyle(.inset(alternatesRowBackgrounds: false))
                    }
                    }
                    .contextMenu(forSelectionType: UUID.self) { selected in
                        if let id = selected.first,
                           let stack = model.allStacks.first(where: { $0.id == id }) {
                            Button("Unregister (keeps the file)") {
                                model.removeStack(stack)
                            }
                        }
                    }
                } inspector: {
                    StackInspector(
                        stack: selectedStack,
                        model: model,
                        onEdit: { openedStackID = selectedStack?.id }
                    )
                }
            }

            if let stackMessage = model.stackMessage {
                MessageCard(title: stackMessage, icon: .info, tint: .secondary)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }
        }
        .background(theme.windowBackground)
        .navigationDestination(item: $openedStackID) { id in
            if let stack = model.allStacks.first(where: { $0.id == id }) {
                StackDetailView(stack: stack, model: model)
            }
        }
        .toolbar {
            ToolbarItem {
                Button("Add Existing\u{2026}") { pickExistingFile() }
            }
            ToolbarItem {
                Button("New Stack\u{2026}") { showingNewStack = true }
            }
        }
        .sheet(isPresented: $showingNewStack) {
            NewStackSheet(name: $newStackName, directory: $newStackDirectory) {
                guard let directory = newStackDirectory else { return }
                Task {
                    await model.createStack(named: newStackName, in: directory)
                }
                showingNewStack = false
                newStackName = ""
                newStackDirectory = nil
            }
        }
        .task {
            await model.refreshStacks()
        }
    }

    private var filteredStacks: [ComposeStack] {
        model.allStacks.filter { stack in
            ResourceSearch.matches(searchText, stack.name, stack.fileURL.path)
        }
    }

    private var selectedStack: ComposeStack? {
        guard let selectedStackID else { return nil }
        return model.allStacks.first { $0.id == selectedStackID }
    }

    private func pickExistingFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        let yamlTypes = [
            UTType(filenameExtension: "yml"),
            UTType(filenameExtension: "yaml"),
        ].compactMap { $0 }
        panel.allowedContentTypes = yamlTypes.isEmpty ? [.plainText] : yamlTypes
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.addStack(fileURL: url) }
    }
}

struct StackActionAvailability: Equatable {
    let canControl: Bool
    let canEdit: Bool

    init(isHealthy: Bool, isBusy: Bool) {
        canControl = isHealthy && !isBusy
        canEdit = !isBusy
    }
}

private struct StackInspector: View {
    let stack: ComposeStack?
    let model: RuntimeViewModel
    let onEdit: () -> Void

    private var statuses: [ComposeServiceStatus] {
        guard let stack else { return [] }
        return model.stackStatuses[stack.id] ?? []
    }

    var body: some View {
        if let stack {
            VStack(alignment: .leading, spacing: 0) {
                InspectorHeader(
                    title: stack.name,
                    subtitle: stack.fileURL.path,
                    pill: statuses.isEmpty
                        ? nil : "\(statuses.filter(\.isRunning).count)/\(statuses.count)"
                ) {
                    let availability = StackActionAvailability(
                        isHealthy: model.isHealthy,
                        isBusy: model.busyStackID != nil
                    )
                    InspectorAction(title: "Start", prominent: true) {
                        Task { await model.upStack(stack) }
                    }
                    .disabled(!availability.canControl)
                    InspectorAction(title: "Stop") {
                        Task { await model.downStack(stack, removeVolumes: false) }
                    }
                    .disabled(!availability.canControl)
                    InspectorAction(title: "Edit") {
                        onEdit()
                    }
                    .disabled(!availability.canEdit)
                }

                InspectorStatBlock(
                    rows: [
                        ("File", stack.fileURL.lastPathComponent, true),
                        ("Directory", stack.projectDirectory.path, true),
                        (
                            "Services",
                            statuses.isEmpty
                                ? "—"
                                : statuses.map(\.name).joined(separator: ", "),
                            false
                        ),
                        (
                            "Status",
                            statuses.isEmpty
                                ? "—"
                                : statuses.map { "\($0.name) \($0.state)" }.joined(separator: ", "),
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

private struct NewStackSheet: View {
    @Binding var name: String
    @Binding var directory: URL?
    let onCreate: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Stack")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("my-stack", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { submit() }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Directory")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text(directory?.path ?? "No directory chosen")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose\u{2026}") { directory = pickDirectory() }
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") { submit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedName.isEmpty || directory == nil)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func submit() {
        guard !trimmedName.isEmpty, directory != nil else { return }
        onCreate()
    }

    private func pickDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
