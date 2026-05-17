import SwiftUI
import AppKit

struct MenuView: View {
    @Bindable var state: AppState
    // SettingsLink doesn't reliably surface the window from a MenuBarExtra
    // in an LSUIElement app; the programmatic action + explicit app
    // activation does (accessory apps aren't activated automatically).
    @Environment(\.openSettings) private var openSettings

    /// Only real applications are listed — `nettop` sees every daemon on the
    /// box, but a per-app data-saver is about apps. System/CLI processes are
    /// still counted in the header total (honest), just not shown as rows.
    private var rows: [AppEntry] {
        state.apps.values
            .filter { URL(fileURLWithPath: $0.path).pathExtension == "app" }
            .sorted {
                (state.usage[$0.id]?.total ?? 0)
                    > (state.usage[$1.id]?.total ?? 0)
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if rows.isEmpty {
                ContentUnavailableView("No traffic yet",
                    systemImage: "antenna.radiowaves.left.and.right",
                    description: Text(state.enabled
                        ? "Apps appear here as they connect."
                        : "Turn on to start filtering."))
                    .frame(height: 180)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(rows) { app in
                            AppRow(app: app,
                                   usage: state.usage[app.id],
                                   rate: state.liveRate[app.id],
                                   total: state.totalBytes,
                                   choked: state.enabled) { allowed in
                                state.setAllowed(app.id, allowed)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(height: 320)
            }
        }
        .frame(width: 360)
    }

    // The on/off switch leads (the product's primary action), the headline
    // metric — total used today — sits on the same row so the effect of the
    // switch reads at a glance, and Settings closes it out.
    private var header: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(get: { state.enabled },
                                     set: { state.setEnabled($0) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.large)
                .accessibilityLabel("Data filtering")

            Spacer()

            HStack(spacing: 6) {
                if state.capReached {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .accessibilityLabel("Data cap reached")
                }
                Text(AppState.fmt(state.totalBytes))
                    .font(.system(.title2, design: .rounded)
                            .weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(state.capReached ? .red : .primary)
                    .contentTransition(.numericText())
            }

            Spacer()

            Button {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityLabel("Settings")
        }
        .padding(12)
    }
}
