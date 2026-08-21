import Foundation

/// Which copy of Apple `container` to drive.
public enum RuntimeSource: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Prefer the vendored copy, then fall back to whatever the machine has.
    case automatic
    /// Only the copy shipped inside the app bundle.
    case bundled
    /// Only a Homebrew install, preferring the version-pinned keg.
    case homebrew

    public var id: Self { self }

    public var title: String {
        switch self {
        case .automatic: "Automatic"
        case .bundled: "Bundled with ContainerStack"
        case .homebrew: "Homebrew"
        }
    }

    public var detail: String {
        switch self {
        case .automatic:
            "Use the bundled runtime when present, otherwise a system install."
        case .bundled:
            "Pinned to \(RuntimeProcessConfiguration.pinnedContainerVersion) and unaffected by brew upgrade."
        case .homebrew:
            "Prefers the container@\(RuntimeProcessConfiguration.pinnedContainerVersion) keg, "
                + "then any container on the usual Homebrew paths."
        }
    }
}

/// Settings shared between the app and the runtime helper.
///
/// A file rather than `UserDefaults`: the helper is a separate executable in
/// `Contents/Helpers` with its own defaults domain, and the LaunchAgent starts it without
/// the app running at all, so a preference written by the app would never reach it.
public struct RuntimePreferences: Codable, Equatable, Sendable {
    public var runtimeSource: RuntimeSource

    public init(runtimeSource: RuntimeSource = .automatic) {
        self.runtimeSource = runtimeSource
    }

    public static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/ContainerStack/runtime-preferences.json")
    }

    /// Never throws: a missing or unreadable file means "defaults", which is what a first
    /// run looks like. The helper must start even if this file is corrupt.
    public static func load(from url: URL = fileURL) -> RuntimePreferences {
        guard
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(RuntimePreferences.self, from: data)
        else { return RuntimePreferences() }
        return decoded
    }

    public func save(to url: URL = fileURL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
