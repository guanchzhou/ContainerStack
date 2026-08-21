import ContainerStackCore
import Foundation

/// One row of the Activity Monitor. A flat, `Comparable`-friendly value so `Table` can sort
/// on any column by key path without reaching into nested optionals.
struct ContainerResourceRow: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let image: String
    /// Percent of the container's own core allocation. `nil` until the first sample lands.
    let cpuPercent: Double?
    let memoryUsed: Int64?
    /// This container's own micro-VM limit, not a figure shared with every other container.
    let memoryLimit: Int64?
    let allocatedCpus: Double?
    let networkReceived: Int64?
    let networkSent: Int64?
    let blockRead: Int64?
    let blockWritten: Int64?
    let processCount: Int?
    /// True when the last poll failed and these numbers are the previous good sample.
    let isStale: Bool

    // Sort keys: Table needs non-optional comparables, and "unknown last" beats "unknown as 0".
    var cpuSortKey: Double { cpuPercent ?? -1 }
    var memorySortKey: Int64 { memoryUsed ?? -1 }
    var networkSortKey: Int64 { (networkReceived ?? 0) + (networkSent ?? 0) }
    var diskSortKey: Int64 { (blockRead ?? 0) + (blockWritten ?? 0) }
    var processSortKey: Int { processCount ?? -1 }

    var memoryFraction: Double? {
        guard let memoryUsed, let memoryLimit, memoryLimit > 0 else { return nil }
        return Double(memoryUsed) / Double(memoryLimit)
    }
}

extension RuntimeViewModel {
    /// Samples every running container once. Allocation is fetched only the first time a
    /// container is seen: it is fixed for the container's lifetime, so re-reading it on every
    /// tick would double the request count for a value that cannot change.
    func refreshContainerStats() async {
        let running = containers.filter(\.isRunning)
        guard !running.isEmpty else {
            resourceRows = []
            return
        }

        var rows: [ContainerResourceRow] = []
        rows.reserveCapacity(running.count)

        for container in running {
            if allocations[container.id] == nil {
                allocations[container.id] = try? await client.containerAllocation(id: container.id)
            }
            let allocation = allocations[container.id] ?? nil
            let previous = resourceRows.first { $0.id == container.id }

            guard let sample = try? await client.containerStats(id: container.id) else {
                // Keep the last good numbers and mark them stale rather than blanking the
                // row: a single dropped sample should not make the table flicker to empty.
                if let previous {
                    rows.append(staleCopy(of: previous))
                }
                continue
            }

            rows.append(
                ContainerResourceRow(
                    id: container.id,
                    name: container.name,
                    image: container.image ?? "—",
                    cpuPercent: sample.cpuPercent(allocatedCpus: allocation?.cpus),
                    memoryUsed: sample.memoryUsage,
                    memoryLimit: sample.memoryLimit ?? allocation?.memoryBytes,
                    allocatedCpus: allocation?.cpus,
                    networkReceived: sample.networkReceived,
                    networkSent: sample.networkSent,
                    blockRead: sample.blockRead,
                    blockWritten: sample.blockWritten,
                    processCount: sample.processCount,
                    isStale: false
                )
            )
        }

        resourceRows = rows
        // Drop cached allocations for containers that no longer exist.
        let live = Set(running.map(\.id))
        allocations = allocations.filter { live.contains($0.key) }
    }

    private func staleCopy(of row: ContainerResourceRow) -> ContainerResourceRow {
        ContainerResourceRow(
            id: row.id,
            name: row.name,
            image: row.image,
            cpuPercent: row.cpuPercent,
            memoryUsed: row.memoryUsed,
            memoryLimit: row.memoryLimit,
            allocatedCpus: row.allocatedCpus,
            networkReceived: row.networkReceived,
            networkSent: row.networkSent,
            blockRead: row.blockRead,
            blockWritten: row.blockWritten,
            processCount: row.processCount,
            isStale: true
        )
    }

    /// Separate from `startMonitoring` so sampling only runs while the Activity Monitor is
    /// on screen — there is no reason to poll every container while looking at Images.
    func startSamplingStats(interval: Duration = .seconds(2)) {
        guard statsTask == nil else { return }
        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshContainerStats()
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stopSamplingStats() {
        statsTask?.cancel()
        statsTask = nil
    }
}
