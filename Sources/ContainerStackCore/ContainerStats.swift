import Foundation

/// A single `GET /containers/{id}/stats?stream=false` sample.
///
/// The payload carries its own previous sample (`precpu_stats` plus the `preread`
/// timestamp), so CPU time is a delta within one response — no need to hold a prior
/// sample or to blank the first row.
public struct ContainerStatsSample: Decodable, Equatable, Sendable {
    public struct CPUUsage: Decodable, Equatable, Sendable {
        public let totalUsage: Int64

        enum CodingKeys: String, CodingKey {
            case totalUsage = "total_usage"
        }
    }

    public struct CPUStats: Decodable, Equatable, Sendable {
        public let cpuUsage: CPUUsage
        public let onlineCpus: Int?

        enum CodingKeys: String, CodingKey {
            case cpuUsage = "cpu_usage"
            case onlineCpus = "online_cpus"
        }
    }

    public struct MemoryStats: Decodable, Equatable, Sendable {
        public let usage: Int64?
        public let limit: Int64?
    }

    public struct NetworkStats: Decodable, Equatable, Sendable {
        public let rxBytes: Int64?
        public let txBytes: Int64?

        enum CodingKeys: String, CodingKey {
            case rxBytes = "rx_bytes"
            case txBytes = "tx_bytes"
        }
    }

    public struct BlkioEntry: Decodable, Equatable, Sendable {
        public let op: String
        public let value: Int64
    }

    public struct BlkioStats: Decodable, Equatable, Sendable {
        public let entries: [BlkioEntry]?

        enum CodingKeys: String, CodingKey {
            case entries = "io_service_bytes_recursive"
        }
    }

    public struct PidsStats: Decodable, Equatable, Sendable {
        public let current: Int?
    }

    public let id: String?
    public let name: String?
    public let read: String?
    public let preread: String?
    public let cpuStats: CPUStats
    public let precpuStats: CPUStats
    public let memoryStats: MemoryStats?
    public let networks: [String: NetworkStats]?
    public let blkioStats: BlkioStats?
    public let pidsStats: PidsStats?

    enum CodingKeys: String, CodingKey {
        case id, name, read, preread, networks
        case cpuStats = "cpu_stats"
        case precpuStats = "precpu_stats"
        case memoryStats = "memory_stats"
        case blkioStats = "blkio_stats"
        case pidsStats = "pids_stats"
    }

    // MARK: Derived

    public var memoryUsage: Int64? { memoryStats?.usage }

    /// The limit of *this container's own micro-VM*, not a shared allocation.
    public var memoryLimit: Int64? { memoryStats?.limit }

    public var memoryFraction: Double? {
        guard let usage = memoryUsage, let limit = memoryLimit, limit > 0 else { return nil }
        return Double(usage) / Double(limit)
    }

    public var networkReceived: Int64? { sum(\.rxBytes) }
    public var networkSent: Int64? { sum(\.txBytes) }

    public var blockRead: Int64? { blkio("read") }
    public var blockWritten: Int64? { blkio("write") }

    public var processCount: Int? { pidsStats?.current }

    public var elapsedSeconds: Double? {
        guard
            let read = Self.date(from: read),
            let preread = Self.date(from: preread)
        else { return nil }
        let elapsed = read.timeIntervalSince(preread)
        return elapsed > 0 ? elapsed : nil
    }

    /// CPU use as a percentage of what this container was actually allocated.
    ///
    /// Deliberately **not** Docker's `cpuDelta / systemDelta * online_cpus`. Two reasons,
    /// both measured against Apple `container` 1.2.2 through socktainer:
    ///
    /// 1. `system_cpu_usage` is not comparable to Docker's — it came back as `0` in
    ///    `precpu_stats` and as less than the container's own `total_usage` in
    ///    `cpu_stats`, so it cannot serve as a denominator.
    /// 2. `online_cpus` reports the **host** core count (10 here) while the container is
    ///    allocated `HostConfig.NanoCpus` (4). Dividing by the host count understates
    ///    usage by the ratio between them.
    ///
    /// So: CPU-seconds consumed over wall-clock seconds elapsed, normalised by the
    /// container's own core allocation. `online_cpus` is only a fallback.
    public func cpuPercent(allocatedCpus: Double?) -> Double? {
        guard let elapsed = elapsedSeconds else { return nil }

        let delta = cpuStats.cpuUsage.totalUsage - precpuStats.cpuUsage.totalUsage
        guard delta >= 0 else { return 0 }  // counter reset on restart

        let cores = allocatedCpus ?? cpuStats.onlineCpus.map(Double.init) ?? 1
        guard cores > 0 else { return nil }

        let cpuSeconds = Double(delta) / 1_000_000_000
        return cpuSeconds / elapsed / cores * 100
    }

    // MARK: Helpers

    private func sum(_ field: KeyPath<NetworkStats, Int64?>) -> Int64? {
        guard let networks, !networks.isEmpty else { return nil }
        return networks.values.reduce(into: Int64(0)) { $0 += $1[keyPath: field] ?? 0 }
    }

    private func blkio(_ op: String) -> Int64? {
        guard let entries = blkioStats?.entries else { return nil }
        let matching = entries.filter { $0.op.caseInsensitiveCompare(op) == .orderedSame }
        return matching.isEmpty ? nil : matching.reduce(into: Int64(0)) { $0 += $1.value }
    }

    /// The runtime sends fractional seconds, but not every field is guaranteed to, so
    /// both shapes are accepted rather than failing the whole sample on a format nit.
    static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        // Value-type strategies rather than a shared ISO8601DateFormatter: the latter is
        // not Sendable, so a static instance cannot be held under strict concurrency.
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value) {
            return date
        }
        return try? Date.ISO8601FormatStyle(includingFractionalSeconds: false).parse(value)
    }
}

/// What the runtime gave this container's micro-VM. Fixed for the container's lifetime,
/// so it is fetched once and cached rather than polled.
public struct ContainerAllocation: Equatable, Sendable {
    public let memoryBytes: Int64?
    public let nanoCpus: Int64?

    public init(memoryBytes: Int64?, nanoCpus: Int64?) {
        self.memoryBytes = memoryBytes
        self.nanoCpus = nanoCpus
    }

    public var cpus: Double? {
        guard let nanoCpus, nanoCpus > 0 else { return nil }
        return Double(nanoCpus) / 1_000_000_000
    }
}
