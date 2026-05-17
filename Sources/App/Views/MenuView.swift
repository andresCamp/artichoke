import SwiftUI

struct MenuView: View {
    @Bindable var state: AppState
    @State private var showSettings = false

    private var rows: [AppEntry] {
        state.apps.values.sorted {
            (state.usage[$0.id]?.total ?? 0) > (state.usage[$1.id]?.total ?? 0)
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
                                   rate: state.liveRate[app.id]) { allowed in
                                state.setAllowed(app.id, allowed)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(height: 320)
            }
            if showSettings { Divider(); settings }
        }
        .frame(width: 360)
    }

    private var header: some View {
        VStack(spacing: 12) {
            // The on/off switch is the product's primary action, so it
            // leads the header at a large control size — unlabeled, since
            // a switch already reads as on/off and the usage number below
            // makes the effect obvious.
            HStack {
                Toggle("", isOn: Binding(get: { state.enabled },
                                         set: { state.setEnabled($0) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.large)
                    .accessibilityLabel("Data filtering")

                Spacer()

                Button { showSettings.toggle() } label: {
                    Image(systemName: "gearshape")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityLabel("Settings")
            }

            // The headline metric for a cap-driven app: total used today.
            HStack(spacing: 6) {
                if state.capReached {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .accessibilityLabel("Data cap reached")
                }
                Text(AppState.fmt(state.totalBytes))
                    .font(.system(.largeTitle, design: .rounded)
                            .weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(state.capReached ? .red : .primary)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Block new apps by default",
                   isOn: Binding(get: { !state.allowUnknownByDefault },
                                 set: { state.allowUnknownByDefault = !$0 }))
            Toggle("Auto-on when on a hotspot",
                   isOn: $state.autoOnHotspot)
            HStack {
                Text("Data cap")
                Spacer()
                TextField("0", value: $state.capMB, format: .number)
                    .frame(width: 60).multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                Text("MB · 0 = off").foregroundStyle(.secondary)
            }
            HStack {
                Circle()
                    .fill(state.onHotspot ? .orange : .secondary)
                    .frame(width: 7, height: 7)
                Text(state.onHotspot ? "On hotspot" : "Normal network")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(state.extensionStatus)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("Quit Artichoke") { NSApp.terminate(nil) }
                .buttonStyle(.plain).foregroundStyle(.red)
        }
        .padding(12)
        .font(.callout)
        .toggleStyle(.checkbox)
    }
}
