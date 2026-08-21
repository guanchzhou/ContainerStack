import ContainerStackCore
import SwiftUI

/// Deliberately sparse: one decision, its consequence, and the resolved path so the choice
/// is verifiable. Anything else belongs on a screen that has earned it.
struct SettingsView: View {
    let model: RuntimeViewModel
    @State private var source: RuntimeSource = RuntimePreferences.load().runtimeSource
    @State private var saveError: String?

    var body: some View {
        Form {
            Section {
                Picker("Container runtime", selection: $source) {
                    ForEach(RuntimeSource.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.inline)
            } header: {
                Text("Runtime")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(source.detail)
                    LabeledContent("Resolves to") {
                        Text(resolvedPath)
                            .monospaced()
                            .textSelection(.enabled)
                            .truncationMode(.middle)
                    }
                    if let override {
                        Label(
                            "CONTAINERSTACK_CONTAINER_PATH is set and overrides this setting.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.orange)
                        Text(override).monospaced().foregroundStyle(.secondary)
                    }
                    if let saveError {
                        Label(saveError, systemImage: "xmark.circle").foregroundStyle(.red)
                    }
                }
                .font(.callout)
            }

            Section {
                Button("Restart Runtime") { Task { _ = await model.restartRuntime() } }
                    .disabled(model.isRestarting)
            } footer: {
                Text("A change takes effect when the runtime restarts.")
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: source) { _, newValue in
            do {
                try RuntimePreferences(runtimeSource: newValue).save()
                saveError = nil
            } catch {
                saveError = "Could not save: \(error.localizedDescription)"
            }
        }
    }

    private var override: String? {
        let value = ProcessInfo.processInfo.environment["CONTAINERSTACK_CONTAINER_PATH"]
        return (value?.isEmpty ?? true) ? nil : value
    }

    /// Shown rather than described: the whole point of the setting is which binary runs, and
    /// this machine may not have the one the option names.
    private var resolvedPath: String {
        RuntimeProcessConfiguration.make(
            socktainerPath: "",
            source: source,
            bundledInstallRoot: RuntimeProcessConfiguration.bundledInstallRoot(
                forExecutableAt: Bundle.main.executableURL
            )
        ).containerPath
    }
}
