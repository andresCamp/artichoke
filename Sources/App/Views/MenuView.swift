import SwiftUI

enum ViewMode: String, CaseIterable { case today = "Today"
                                       case live  = "Live monitor" }

struct MenuView: View {
    @Bindable var state: AppState
    @State private var mode: ViewMode = .today
    @State private var showSettings = false

    private var rows: [AppEntry] {
        state.apps.values.sorted {
            (state.usage[$0.id]?.total ?? 0) > (state.usage[$1.id]?.total ?? 0)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
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
                            AppRow(app: app, mode: mode,
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
        HStack(alignment: .center) {
            Toggle("", isOn: Binding(get: { state.enabled },
                                     set: { state.setEnabled($0) }))
                .toggleStyle(.switch)
                .labelsHidden()

            Spacer()

            VStack(spacing: 2) {
                Text(AppState.fmt(state.totalBytes))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(state.capReached ? .red : .primary)
                Picker("", selection: $mode) {
                    ForEach(ViewMode.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }

            Spacer()

            Button { showSettings.toggle() } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.plain)
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
    }
}
