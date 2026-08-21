import Foundation

private struct HostConfigPayload: Decodable {
    struct HostConfig: Decodable {
        let memory: Int64?
        let nanoCpus: Int64?

        enum CodingKeys: String, CodingKey {
            case memory = "Memory"
            case nanoCpus = "NanoCpus"
        }
    }

    let hostConfig: HostConfig?

    enum CodingKeys: String, CodingKey {
        case hostConfig = "HostConfig"
    }
}

extension DockerAPIClient {
    /// `stream=false` returns a single sample and closes, so this is a normal request
    /// rather than a long-lived stream.
    public func containerStats(id: String) async throws -> ContainerStatsSample {
        let response = try await request(path: "/containers/\(Self.pathEncoded(id))/stats?stream=false")
        return try await decode(ContainerStatsSample.self, response: response)
    }

    /// Reads `HostConfig.Memory` and `HostConfig.NanoCpus` from container inspect. Both are
    /// available over the socket, so the per-container allocation needs no `container` CLI.
    public func containerAllocation(id: String) async throws -> ContainerAllocation {
        let response = try await request(path: "/containers/\(Self.pathEncoded(id))/json")
        let payload = try await decode(HostConfigPayload.self, response: response)
        return ContainerAllocation(
            memoryBytes: payload.hostConfig?.memory,
            nanoCpus: payload.hostConfig?.nanoCpus
        )
    }
}
