import SwiftUI
import AppKit

/// The standard macOS Settings window (⌘,). Grouped Form with explained
/// settings, progressive-disclosure data cap, and a status section that
/// surfaces the system-extension state instead of whispering it.
struct SettingsView: View {
    @Bindable var state: AppState

    /// Drives the cap on/off without exposing the "0 = off" sentinel.
    /// Turning it on seeds a sensible default; off zeroes it.
    private var capEnabled: Binding<Bool> {
        Binding(get: { state.capMB > 0 },
                set: { state.capMB = $0 ? max(state.capMB, 1_000) : 0 })
    }

    private var extensionError: String? {
        let s = state.extensionStatus
        return s.localizedCaseInsensitiveContains("error")
            || s.localizedCaseInsensitiveContains("approve")
            ? s : nil
    }

    var body: some View {
        Form {
            Section("Behavior") {
                Toggle(isOn: Binding(
                    get: { !state.allowUnknownByDefault },
                    set: { state.allowUnknownByDefault = !$0 })) {
                    Text("Block new apps by default")
                    Text("New apps stay denied until you allow them.")
                }
                Toggle(isOn: $state.autoOnHotspot) {
                    Text("Turn on automatically for hotspots")
                    Text("Starts filtering when you join a personal hotspot.")
                }
            }

            Section("Daily data cap") {
                Toggle("Limit daily data", isOn: capEnabled)
                if state.capMB > 0 {
                    LabeledContent("Block all traffic after") {
                        HStack(spacing: 6) {
                            TextField("", value: $state.capMB,
                                      format: .number)
                                .labelsHidden()
                                .frame(width: 72)
                                .multilineTextAlignment(.trailing)
                            Stepper("", value: $state.capMB,
                                    in: 1...1_000_000, step: 100)
                                .labelsHidden()
                            Text("MB")
                        }
                    }
                    Text("The counter resets at midnight.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Status") {
                LabeledContent {
                    Text(state.onHotspot ? "On hotspot" : "Normal")
                        .foregroundStyle(.secondary)
                } label: {
                    Label("Network",
                          systemImage: "antenna.radiowaves.left.and.right")
                }
                LabeledContent {
                    Text(state.extensionStatus)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                } label: {
                    Label("Filter extension",
                          systemImage: "puzzlepiece.extension.fill")
                }
                if let err = extensionError {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(err).fixedSize(horizontal: false,
                                                vertical: true)
                            Button("Open System Settings…") {
                                openExtensionSettings()
                            }
                            .buttonStyle(.link)
                        }
                    }
                    .font(.callout)
                }
            }

            Section {
                Button("Quit Artichoke", role: .destructive) {
                    NSApp.terminate(nil)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 480)
    }

    private func openExtensionSettings() {
        // Login Items & Extensions ▸ Network Extensions (macOS 13+).
        let url = URL(string:
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
        NSWorkspace.shared.open(url ??
            URL(string: "x-apple.systempreferences:")!)
    }
}
