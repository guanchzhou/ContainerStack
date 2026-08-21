import Foundation
import Testing

@testable import ContainerStackCore

/// Captured verbatim from `GET /containers/{id}/stats?stream=false` against socktainer on
/// Apple `container` 1.2.2, so the decoder is pinned to a shape the runtime really sends —
/// including `system_cpu_usage: 0` in `precpu_stats`, which is why the Docker CPU formula
/// is unusable here.
private let liveSample = """
{
  "name": "/arango",
  "os_type": "linux",
  "read": "2026-08-21T18:38:01.299Z",
  "preread": "2026-08-21T18:38:00.226Z",
  "id": "5ead6aeeb1ef6d6b62e5e16d7bebe40c6bf6cc2ce12cf5b06edee4d7722d9524",
  "precpu_stats": {
    "online_cpus": 10,
    "cpu_usage": { "usage_in_usermode": 57261311000, "total_usage": 57261311000, "usage_in_kernelmode": 0 },
    "system_cpu_usage": 0
  },
  "storage_stats": {},
  "networks": {
    "eth0": { "rx_bytes": 7961875, "tx_bytes": 10351519182, "rx_packets": 0, "tx_packets": 0,
              "rx_errors": 0, "tx_errors": 0, "rx_dropped": 0, "tx_dropped": 0 }
  },
  "pids_stats": { "current": 59 },
  "cpu_stats": {
    "online_cpus": 10,
    "cpu_usage": { "usage_in_usermode": 57267217000, "total_usage": 57267217000, "usage_in_kernelmode": 0 },
    "system_cpu_usage": 10728750220
  },
  "blkio_stats": {
    "io_service_bytes_recursive": [
      { "op": "read", "value": 98807808, "major": 8, "minor": 0 },
      { "op": "write", "value": 4096, "major": 8, "minor": 0 }
    ]
  },
  "num_procs": 0,
  "memory_stats": { "limit": 6442450944, "usage": 5937504256 }
}
"""

private func sample(_ json: String = liveSample) throws -> ContainerStatsSample {
    try JSONDecoder().decode(ContainerStatsSample.self, from: Data(json.utf8))
}

struct ContainerStatsTests {
    @Test
    func decodesTheShapeTheRuntimeActuallySends() throws {
        let stats = try sample()
        #expect(stats.name == "/arango")
        #expect(stats.memoryUsage == 5_937_504_256)
        #expect(stats.memoryLimit == 6_442_450_944)
        #expect(stats.processCount == 59)
        #expect(stats.networkReceived == 7_961_875)
        #expect(stats.networkSent == 10_351_519_182)
        #expect(stats.blockRead == 98_807_808)
        #expect(stats.blockWritten == 4096)
        #expect(stats.cpuStats.onlineCpus == 10)
    }

    @Test
    func elapsedComesFromReadMinusPreread() throws {
        let elapsed = try #require(try sample().elapsedSeconds)
        #expect(abs(elapsed - 1.073) < 0.001)
    }

    /// 5,906,000 ns of CPU over 1.073 s, normalised by the container's own 4 cores.
    @Test
    func cpuPercentNormalisesByTheContainersOwnAllocation() throws {
        let percent = try #require(try sample().cpuPercent(allocatedCpus: 4))
        #expect(abs(percent - 0.1376) < 0.001)
    }

    /// The same sample against the host's 10 cores reads 2.5x lower — which is exactly the
    /// error Docker's `online_cpus` denominator would introduce here.
    @Test
    func onlineCpusIsOnlyAFallbackAndReadsDifferently() throws {
        let fallback = try #require(try sample().cpuPercent(allocatedCpus: nil))
        #expect(abs(fallback - 0.0550) < 0.001)
    }

    @Test
    func counterResetReportsZeroRatherThanNegative() throws {
        let reset = liveSample.replacingOccurrences(
            of: "\"total_usage\": 57267217000",
            with: "\"total_usage\": 12"
        )
        #expect(try sample(reset).cpuPercent(allocatedCpus: 4) == 0)
    }

    @Test
    func zeroElapsedYieldsNoPercentageRatherThanDividingByZero() throws {
        let frozen = liveSample.replacingOccurrences(
            of: "\"preread\": \"2026-08-21T18:38:00.226Z\"",
            with: "\"preread\": \"2026-08-21T18:38:01.299Z\""
        )
        #expect(try sample(frozen).elapsedSeconds == nil)
        #expect(try sample(frozen).cpuPercent(allocatedCpus: 4) == nil)
    }

    @Test
    func memoryFractionIsAgainstTheContainersOwnVMLimit() throws {
        let fraction = try #require(try sample().memoryFraction)
        #expect(abs(fraction - 0.9216) < 0.001)
    }

    @Test
    func allocationConvertsNanoCpus() {
        #expect(ContainerAllocation(memoryBytes: 6_442_450_944, nanoCpus: 4_000_000_000).cpus == 4)
        #expect(ContainerAllocation(memoryBytes: nil, nanoCpus: 0).cpus == nil)
        #expect(ContainerAllocation(memoryBytes: nil, nanoCpus: nil).cpus == nil)
    }
}
