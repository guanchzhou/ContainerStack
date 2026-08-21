import ContainerStackCore
import SwiftUI

/// The landing screen: what each container is actually consuming, against the allocation of
/// its own micro-VM.
///
/// Built with SwiftUI `Table` rather than the hand-rolled rows used elsewhere, which is what
/// supplies column sorting, resizing, keyboard navigation and VoiceOver without writing any
/// of it — and what lets the content fill the pane instead of leaving it empty.
struct ActivityMonitorView: View {
    let model: RuntimeViewModel
    @State private var sortOrder = [KeyPathComparator(\ContainerResourceRow.cpuSortKey, order: .reverse)]

    var body: some View {
        Group {
            if rows.isEmpty {
                // Native empty state rather than the Lucide-based EmptyResourceView: this
                // screen is where the move to system components starts.
                ContentUnavailableView(
                    model.containers.isEmpty ? "No containers" : "Nothing running",
                    systemImage: "gauge.with.dots.needle.33percent",
                    description: Text(
                        model.containers.isEmpty
                            ? "Run an image to see live resource use here."
                            : "Start a container to see its CPU, memory and I/O."
                    )
                )
            } else {
                table
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .task {
            await model.refreshDiskUsage()
            model.startSamplingStats()
        }
        .onDisappear { model.stopSamplingStats() }
    }

    private var rows: [ContainerResourceRow] {
        model.resourceRows.sorted(using: sortOrder)
    }

    private var table: some View {
        Table(rows, sortOrder: $sortOrder) {
            TableColumn("Container", value: \.name) { row in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(row.name).fontWeight(.medium)
                        if row.isStale {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .help("Last sample failed — showing the previous reading")
                                .accessibilityLabel("Stale reading")
                        }
                    }
                    Text(row.image)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .width(min: 160, ideal: 240)

            TableColumn("CPU", value: \.cpuSortKey) { row in
                if let cpu = row.cpuPercent {
                    Text(cpu, format: .number.precision(.fractionLength(1)))
                        .monospacedDigit()
                        + Text("%").foregroundStyle(.secondary)
                } else {
                    unknown
                }
            }
            .width(min: 60, ideal: 72)

            TableColumn("Memory", value: \.memorySortKey) { row in
                MemoryCell(row: row)
            }
            .width(min: 130, ideal: 190)

            TableColumn("Net I/O", value: \.networkSortKey) { row in
                pair(down: row.networkReceived, up: row.networkSent)
            }
            .width(min: 110, ideal: 140)

            TableColumn("Disk I/O", value: \.diskSortKey) { row in
                pair(down: row.blockRead, up: row.blockWritten)
            }
            .width(min: 110, ideal: 140)

            TableColumn("Procs", value: \.processSortKey) { row in
                if let count = row.processCount {
                    Text(count, format: .number).monospacedDigit()
                } else {
                    unknown
                }
            }
            .width(min: 50, ideal: 62)
        }
        // Without this the table paints ~30 empty striped rows below a single container,
        // which reads as broken rather than as spare capacity.
        .tableStyle(.inset(alternatesRowBackgrounds: false))
    }

    private var unknown: some View {
        Text("—")
            .foregroundStyle(.tertiary)
            .help("Not reported by the runtime")
    }

    private func pair(down: Int64?, up: Int64?) -> some View {
        HStack(spacing: 6) {
            label("arrow.down", down)
            label("arrow.up", up)
        }
        .font(.caption)
        .monospacedDigit()
    }

    private func label(_ symbol: String, _ bytes: Int64?) -> some View {
        HStack(spacing: 1) {
            Image(systemName: symbol).foregroundStyle(.tertiary).imageScale(.small)
            Text(bytes == nil ? "—" : ByteSize.formatted(bytes))
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Label("^[\(model.images.count) image](inflect: true)", systemImage: "square.stack.3d.up")
            Label("^[\(model.volumes.count) volume](inflect: true)", systemImage: "externaldrive")
            Label("^[\(model.networks.count) network](inflect: true)", systemImage: "network")

            Divider().frame(height: 12)

            if let failure = model.diskUsageErrorMessage {
                Label("Image storage unavailable", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(failure)
                Button("Retry") { Task { await model.refreshDiskUsage() } }
                    .buttonStyle(.link)
            } else if let size = model.diskUsage?.layersSize {
                Label(ByteSize.formatted(size), systemImage: "internaldrive")
            } else {
                Label("Image storage not reported", systemImage: "internaldrive")
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .font(.caption)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

/// Used against the container's **own** VM limit. Every competing tool shows memory against
/// one shared VM, because that is all a shared-VM runtime has.
private struct MemoryCell: View {
    let row: ContainerResourceRow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Text(row.memoryUsed == nil ? "—" : ByteSize.formatted(row.memoryUsed))
                    .monospacedDigit()
                if let limit = row.memoryLimit {
                    Text("/ \(ByteSize.formatted(limit))")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .font(.caption)

            if let fraction = row.memoryFraction {
                ProgressView(value: min(fraction, 1))
                    .progressViewStyle(.linear)
                    .tint(fraction > 0.9 ? .red : (fraction > 0.75 ? .orange : .accentColor))
                    .controlSize(.small)
                    .help(accessibleSummary(fraction))
                    .accessibilityLabel(accessibleSummary(fraction))
            }
        }
    }

    private func accessibleSummary(_ fraction: Double) -> String {
        let percent = Int((fraction * 100).rounded())
        guard let cpus = row.allocatedCpus else { return "\(percent)% of its memory limit" }
        return "\(percent)% of its memory limit, \(Int(cpus)) cores allocated"
    }
}
