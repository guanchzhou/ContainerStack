import ContainerStackCore
import SwiftUI

struct ImagesView: View {
    let model: RuntimeViewModel
    var searchText: String = ""
    var focusPull: Bool = false
    var onFocusConsumed: () -> Void = {}
    @FocusState private var pullFocused: Bool
    @State private var selectedImageID: String?
    @State private var imageSort = [KeyPathComparator(\DockerImageSummary.referenceText)]
    @State private var pendingImageDelete: DockerImageSummary?
    @AppStorage(ResourceViewMode.storageKey) private var viewMode = ResourceViewMode.cards.rawValue
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ResourceCreateBar(
                placeholder: "Image reference, for example alpine:3.20",
                actionTitle: "Pull",
                icon: .download,
                isBusy: model.busyResource != nil,
                isEnabled: model.isHealthy,
                focused: $pullFocused
            ) { reference in
                Task { await model.pull(reference: reference) }
            }

            if let error = model.imagesErrorMessage {
                MessageCard(title: error, icon: .triangleAlert, tint: .orange)
                    .padding(.horizontal, 24)
            } else if filteredImages.isEmpty {
                EmptyResourceView(
                    title: model.images.isEmpty ? "No images" : "No matching images",
                    description: model.images.isEmpty
                        ? "Pull an image above, or use the Docker CLI against the ContainerStack socket."
                        : "Nothing matches “\(searchText)”.",
                    icon: .package
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ResourceSplitPane(hasSelection: selectedImage != nil) {
                    // Group so the context menu applies to whichever presentation is active.
                    Group {
                    if viewMode == ResourceViewMode.cards.rawValue {
                        List(selection: $selectedImageID) {
                            ForEach(filteredImages) { image in
                                ImageCardRow(
                                    image: image,
                                    model: model,
                                    onDelete: {
                                        selectedImageID = image.id
                                        pendingImageDelete = image
                                    }
                                )
                                .tag(image.id)
                            }
                        }
                        .listStyle(.inset)
                    } else {
                    Table(filteredImages, selection: $selectedImageID, sortOrder: $imageSort) {
                        TableColumn("Repository", value: \.referenceText) { image in
                            Text(image.referenceText)
                                .fontWeight(.medium)
                                .truncationMode(.middle)
                        }
                        .width(min: 200, ideal: 340)
                        TableColumn("Size", value: \.sizeSortKey) { image in
                            Text(image.size == nil ? "—" : ByteSize.formatted(image.size))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .width(min: 70, ideal: 90)
                        TableColumn("Created", value: \.createdSortKey) { image in
                            Text(image.createdText)
                                .foregroundStyle(.secondary)
                        }
                        .width(min: 90, ideal: 130)
                        TableColumn("Used by", value: \.id) { image in
                            ImageUsageCell(image: image, model: model)
                        }
                        .width(min: 90, ideal: 150)
                    }
                    .tableStyle(.inset(alternatesRowBackgrounds: false))
                    }
                    }
                    .contextMenu(forSelectionType: String.self) { selected in
                        if let id = selected.first,
                           let image = model.images.first(where: { $0.id == id }) {
                            Button("Run Image") {
                                Task { await model.run(image: image.repositoryTags?.first ?? image.id) }
                            }
                            Divider()
                            Button("Delete Image…", role: .destructive) {
                                selectedImageID = id
                                pendingImageDelete = image
                            }
                        }
                    }
                } inspector: {
                    ImageInspector(image: selectedImage, model: model)
                }
                .confirmationDialog(
                    "Delete image \(pendingImageDelete?.referenceText ?? "")?",
                    isPresented: Binding(
                        get: { pendingImageDelete != nil },
                        set: { if !$0 { pendingImageDelete = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Delete Image", role: .destructive) {
                        if let image = pendingImageDelete {
                            Task { await model.remove(image: image) }
                        }
                        pendingImageDelete = nil
                    }
                    Button("Cancel", role: .cancel) { pendingImageDelete = nil }
                } message: {
                    Text("The image is deleted locally and must be pulled again to be used.")
                }
            }

            if let resourceMessage = model.resourceMessage {
                MessageCard(title: resourceMessage, icon: .info, tint: .secondary)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
            }

            if let containerMessage = model.containerMessage {
                MessageCard(title: containerMessage, icon: .info, tint: .secondary)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
            }

            if let containerOutput = model.containerOutput {
                OutputCard(output: containerOutput)
                    .padding(24)
            }
        }
        .background(theme.windowBackground)
        .onChange(of: focusPull) { _, want in
            guard want else { return }
            pullFocused = true
            onFocusConsumed()
        }
        .onAppear {
            guard focusPull else { return }
            pullFocused = true
            onFocusConsumed()
        }
    }

    private var filteredImages: [DockerImageSummary] {
        model.images.filter { image in
            ResourceSearch.matches(
                searchText,
                image.repositoryTags?.joined(separator: " "),
                image.id,
                image.architecture
            )
        }
    }

    private var selectedImage: DockerImageSummary? {
        guard let selectedImageID else { return nil }
        return model.images.first { $0.id == selectedImageID }
    }
}

private struct ImageInspector: View {
    let image: DockerImageSummary?
    let model: RuntimeViewModel

    var body: some View {
        if let image {
            let name = image.repositoryTags?.first ?? ResourceIdentifier.short(image.id)
            let used = ResourceUsage.containers(usingImage: image, from: model.containers)
            VStack(alignment: .leading, spacing: 0) {
                InspectorHeader(title: name, subtitle: ResourceIdentifier.short(image.id)) {
                    InspectorAction(title: "Run", prominent: true) {
                        Task { await model.run(image: name) }
                    }
                    InspectorAction(title: "Delete", destructive: true) {
                        Task { await model.remove(image: image) }
                    }
                }
                .disabled(model.busyResource != nil || model.isRunningContainer || !model.isHealthy)

                InspectorStatBlock(
                    rows: [
                        ("ID", ResourceIdentifier.short(image.id), true),
                        ("Arch", image.architecture ?? "—", true),
                        ("OS", image.operatingSystem ?? "—", false),
                        ("Size", ByteSize.formatted(image.size), false),
                        ("Created", formattedCreated(image.created), false),
                        (
                            "Used by",
                            used.isEmpty ? "—" : used.map(\.name).joined(separator: ", "),
                            false
                        ),
                    ]
                )
            }
        } else {
            EmptyInspector()
        }
    }

    private func formattedCreated(_ created: Int64?) -> String {
        guard let created else { return "—" }
        let date = Date(timeIntervalSince1970: TimeInterval(created))
        return date.formatted(.relative(presentation: .named))
    }
}


/// Extracted because inlining the lookup in a TableColumn builder pushed the type checker
/// past its limit.
private struct ImageUsageCell: View {
    let image: DockerImageSummary
    let model: RuntimeViewModel

    var body: some View {
        let used = ResourceUsage.containers(usingImage: image, from: model.containers)
        Text(used.isEmpty ? "—" : used.map(\.name).joined(separator: ", "))
            .foregroundStyle(.secondary)
            .truncationMode(.middle)
    }
}


/// Extracted so the type checker can cope: a ResourceCard with inline ternaries and two
/// buttons in the same expression exceeded its budget.
private struct ImageCardRow: View {
    let image: DockerImageSummary
    let model: RuntimeViewModel
    let onDelete: () -> Void

    private var subtitle: String? {
        let created = image.createdText
        return created == "—" ? nil : "Created \(created)"
    }

    private var sizeText: String {
        image.size == nil ? "—" : ByteSize.formatted(image.size)
    }

    var body: some View {
        ResourceCard(title: image.referenceText, subtitle: subtitle, trailing: sizeText) {
            Button {
                Task { await model.run(image: image.repositoryTags?.first ?? image.id) }
            } label: {
                Image(systemName: "play")
            }
            .buttonStyle(.borderless)
            .help("Run image")
            .accessibilityLabel("Run \(image.referenceText)")

            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .help("Delete image")
            .accessibilityLabel("Delete \(image.referenceText)")
        }
        .disabled(model.busyResource != nil || !model.isHealthy)
    }
}
