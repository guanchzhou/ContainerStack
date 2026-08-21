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

/// Architecture and OS live on image inspect, not on `/images/json`, so they cannot be
/// filled from the list the way `DockerImageSummary` assumes.
public struct DockerImageDetail: Equatable, Sendable {
    public let architecture: String?
    public let operatingSystem: String?
    public let variant: String?

    public init(architecture: String?, operatingSystem: String?, variant: String?) {
        self.architecture = architecture
        self.operatingSystem = operatingSystem
        self.variant = variant
    }

    /// "linux/arm64 v8", or nil when the runtime reports nothing.
    public var platformText: String? {
        guard let operatingSystem, let architecture else { return nil }
        guard let variant, !variant.isEmpty else { return "\(operatingSystem)/\(architecture)" }
        return "\(operatingSystem)/\(architecture) \(variant)"
    }
}

private struct ImageDetailPayload: Decodable {
    let architecture: String?
    let os: String?
    let variant: String?

    enum CodingKeys: String, CodingKey {
        case architecture = "Architecture"
        case os = "Os"
        case variant = "Variant"
    }
}

extension DockerAPIClient {
    /// Resolves **by repository tag**, not by id: socktainer answers 404 for
    /// `/images/{id}/json` while `/images/{repo:tag}/json` returns 200. An untagged image
    /// therefore has no platform to show.
    public func inspectImage(reference: String) async throws -> DockerImageDetail {
        let response = try await request(path: "/images/\(Self.pathEncoded(reference))/json")
        let payload = try await decode(ImageDetailPayload.self, response: response)
        return DockerImageDetail(
            architecture: payload.architecture,
            operatingSystem: payload.os,
            variant: payload.variant
        )
    }
}
