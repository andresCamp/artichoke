import SwiftUI
import AppKit

struct MenuView: View {
    /// Where this view is rendered. The header swaps the pop-out button for
    /// a close button depending on the surface.
    enum Context { case popover, floating }

    @Bindable var state: AppState
    var context: Context = .popover
    // SettingsLink doesn't reliably surface the window from a MenuBarExtra
    // in an LSUIElement app; the programmatic action + explicit app
    // activation does (accessory apps aren't activated automatically).
    @Environment(\.openSettings) private var openSettings
    // Dismisses the transient MenuBarExtra popover when we pop out.
    @Environment(\.dismiss) private var dismiss

    /// One displayed row: a real app, or the synthetic "System" aggregate.
    struct DisplayRow: Identifiable {
        let app: AppEntry
        let usage: UsageCounter
        let bps: UInt64
        let children: [String: UInt64]
        /// Every signing id this row toggles (one app, or all daemons).
        let memberIDs: [String]
        var id: String { app.id }
    }

    /// The System Settings app, for the System row's icon.
    private static let systemSettingsPath: String = {
        let p = "/System/Applications/System Settings.app"
        return FileManager.default.fileExists(atPath: p)
            ? p : "/System/Applications/System Preferences.app"
    }()

    /// Real apps as individual rows (`NettopReader` already folds their
    /// helpers in), heaviest first. Every unattributable daemon / CLI
    /// process (`proc:*`) collapses into one "System" row, pinned last so
    /// the clutter stays out of the way; expanding it lists each daemon.
    private var rows: [DisplayRow] {
        var apps: [DisplayRow] = []
        var sys = UsageCounter()
        var sysBps: UInt64 = 0
        var sysChildren: [String: UInt64] = [:]
        var sysMembers: [String] = []
        var sysAllowed = true

        for e in state.apps.values {
            let u = state.usage[e.id] ?? UsageCounter()
            let r = state.liveRate[e.id]?.inBps ?? 0
            if e.id.hasPrefix("proc:") {
                sys.inBytes &+= u.inBytes
                sys.outBytes &+= u.outBytes
                sysBps &+= r
                if u.total > 0 {
                    sysChildren[e.name.isEmpty ? e.id : e.name,
                                default: 0] &+= u.total
                }
                sysMembers.append(e.id)
                sysAllowed = sysAllowed && e.allowed
            } else {
                apps.append(DisplayRow(
                    app: e, usage: u, bps: r,
                    children: state.breakdown[e.id] ?? [:],
                    memberIDs: [e.id]))
            }
        }
        apps.sort { $0.usage.total > $1.usage.total }

        if !sysMembers.isEmpty {
            let sysApp = AppEntry(id: "__system__", name: "System",
                                  path: Self.systemSettingsPath,
                                  allowed: sysAllowed)
            apps.append(DisplayRow(app: sysApp, usage: sys, bps: sysBps,
                                   children: sysChildren,
                                   memberIDs: sysMembers))
        }
        return apps
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
                        ForEach(rows) { r in
                            AppRow(app: r.app,
                                   usage: r.usage,
                                   rate: (inBps: r.bps, outBps: 0),
                                   total: state.totalBytes,
                                   choked: state.enabled,
                                   children: r.children) { allowed in
                                for id in r.memberIDs {
                                    state.setAllowed(id, allowed)
                                }
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

            HStack(spacing: 14) {
                Button {
                    switch context {
                    case .popover:
                        FloatingPanelController.shared.show(state: state)
                        dismiss()
                    case .floating:
                        FloatingPanelController.shared.close()
                    }
                } label: {
                    Image(systemName: context == .popover
                          ? "arrow.up.forward.app"
                          : "xmark")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityLabel(context == .popover
                                    ? "Open in floating window"
                                    : "Close window")

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
        }
        .padding(12)
    }
}
