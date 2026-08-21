import Foundation
import Testing

@testable import ContainerStackCore

/// Guards the single-owner property: whatever decides the binary must also decide the
/// install root, and the source setting must be honoured everywhere rather than at one of
/// several call sites.
struct RuntimeSourceResolutionTests {
    private let bundleRoot = "/Applications/ContainerStack.app/Contents/Resources/container"
    private var vendored: String { "\(bundleRoot)/bin/container" }
    private var pinnedKeg: String {
        "/opt/homebrew/opt/container@\(RuntimeProcessConfiguration.pinnedContainerVersion)/bin/container"
    }

    private func resolve(
        source: RuntimeSource,
        bundled: String?,
        present: Set<String>,
        environment: [String: String] = [:]
    ) -> RuntimeProcessConfiguration {
        RuntimeProcessConfiguration.make(
            socktainerPath: "/tmp/socktainer",
            source: source,
            bundledInstallRoot: bundled,
            environment: environment,
            exists: { present.contains($0) }
        )
    }

    @Test
    func environmentOverrideBeatsEverySource() {
        for source in RuntimeSource.allCases {
            let config = resolve(
                source: source,
                bundled: bundleRoot,
                present: [vendored, pinnedKeg],
                environment: ["CONTAINERSTACK_CONTAINER_PATH": "/opt/custom/container"]
            )
            #expect(config.containerPath == "/opt/custom/container")
            // An override cannot claim the bundle's install root — it may be a different copy.
            #expect(config.containerInstallRoot == nil)
        }
    }

    @Test
    func bundledUsesTheVendoredCopyAndCarriesItsInstallRoot() {
        let config = resolve(source: .bundled, bundled: bundleRoot, present: [vendored, pinnedKeg])
        #expect(config.containerPath == vendored)
        #expect(config.containerInstallRoot == bundleRoot)
        // The install root is what puts --install-root on `container system start`.
        #expect(config.containerStartArguments == ["system", "start", "--install-root", bundleRoot])
    }

    @Test
    func homebrewNeverPicksTheBundledCopyEvenWhenPresent() {
        let config = resolve(source: .homebrew, bundled: bundleRoot, present: [vendored, pinnedKeg])
        #expect(config.containerPath == pinnedKeg)
        #expect(config.containerInstallRoot == nil)
        // A system install knows its own root, so the flag must be omitted rather than emptied.
        #expect(config.containerStartArguments == ["system", "start"])
    }

    @Test
    func homebrewPrefersTheVersionPinnedKegOverAnUnversionedPath() {
        let config = resolve(
            source: .homebrew,
            bundled: nil,
            present: [pinnedKeg, "/opt/homebrew/bin/container", "/usr/local/bin/container"]
        )
        #expect(config.containerPath == pinnedKeg)
    }

    @Test
    func automaticPrefersVendoredThenFallsBackToTheSystem() {
        let withBundle = resolve(source: .automatic, bundled: bundleRoot, present: [vendored, pinnedKeg])
        #expect(withBundle.containerPath == vendored)
        #expect(withBundle.containerInstallRoot == bundleRoot)

        let withoutBundle = resolve(source: .automatic, bundled: nil, present: [pinnedKeg])
        #expect(withoutBundle.containerPath == pinnedKeg)
        #expect(withoutBundle.containerInstallRoot == nil)
    }

    @Test
    func bundledFallsBackRatherThanReturningAPathThatDoesNotExist() {
        // Asked for bundled on a dev checkout with no staged bundle.
        let config = resolve(source: .bundled, bundled: nil, present: [pinnedKeg])
        #expect(config.containerPath == pinnedKeg)
        #expect(config.containerInstallRoot == nil)
    }

    @Test
    func preferencesRoundTripAndDefaultToAutomaticWhenAbsent() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "cs-prefs-\(UUID().uuidString).json")
        #expect(RuntimePreferences.load(from: url).runtimeSource == .automatic)

        try RuntimePreferences(runtimeSource: .homebrew).save(to: url)
        #expect(RuntimePreferences.load(from: url).runtimeSource == .homebrew)

        // A corrupt file must not stop the helper from starting.
        try Data("not json".utf8).write(to: url)
        #expect(RuntimePreferences.load(from: url).runtimeSource == .automatic)
        try? FileManager.default.removeItem(at: url)
    }
}
