import SwiftUI
import AppKit

/// One row = one user-facing app. `NettopReader` already folds every helper /
/// XPC / renderer process into its parent app, so this is just a clean
/// per-app row. Tapping it expands the real per-process breakdown.
struct AppRow: View {
    let app: AppEntry
    let usage: UsageCounter?
    let rate: (inBps: UInt64, outBps: UInt64)?
    /// Today's grand total — the bar is this app's share of it.
    let total: UInt64
    /// Filtering is on; only then do blocked apps de-emphasize.
    let choked: Bool
    /// process label → bytes, for the expanded line-by-line view.
    let children: [String: UInt64]
    let onToggle: (Bool) -> Void

    @State private var expanded = false
    // The live-rate label lingers briefly after traffic stops so a quick
    // burst doesn't just flicker. Parent re-renders ~1/s, which lets the
    // timed clear fire on schedule.
    @State private var shownBps: UInt64 = 0
    @State private var clearTask: Task<Void, Never>?

    private var icon: NSImage {
        guard !app.path.isEmpty else {
            return NSWorkspace.shared.icon(for: .applicationBundle)
        }
        var url = URL(fileURLWithPath: app.path)
        while url.pathComponents.count > 1 && url.pathExtension != "app" {
            url.deleteLastPathComponent()
        }
        return NSWorkspace.shared.icon(forFile:
            url.pathExtension == "app" ? url.path : app.path)
    }

    /// Heaviest process first; only worth expanding when it's more than the
    /// app's single main process.
    private var sortedChildren: [(name: String, bytes: UInt64)] {
        children.map { ($0.key, $0.value) }
            .sorted { $0.bytes > $1.bytes }
    }
    private var canExpand: Bool { sortedChildren.count > 1 }

    var body: some View {
        VStack(spacing: 0) {
            row
            if expanded {
                VStack(spacing: 4) {
                    ForEach(sortedChildren, id: \.name) { child in
                        HStack {
                            Text(child.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Text(AppState.fmt(child.bytes))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.leading, 60)
                .padding(.trailing, 12)
                .padding(.bottom, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .opacity(dim ? 0.7 : 1)
        .animation(.easeOut(duration: 0.6), value: shownBps)
        .animation(.easeInOut(duration: 0.18), value: expanded)
        .onChange(of: rate?.inBps ?? 0, initial: true) { _, bps in
            if bps > 0 {
                clearTask?.cancel()
                shownBps = bps
            } else if shownBps > 0, clearTask == nil {
                clearTask = Task {
                    try? await Task.sleep(for: .seconds(2.5))
                    if !Task.isCancelled { shownBps = 0 }
                    clearTask = nil
                }
            }
        }
    }

    private var row: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { app.allowed },
                                     set: { onToggle($0) }))
                .toggleStyle(.checkbox).labelsHidden()
                .accessibilityLabel("Allow \(app.name)")

            Image(nsImage: icon).resizable()
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(app.name).lineLimit(1)
                        .foregroundStyle(dim ? .secondary : .primary)
                    if canExpand {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                    Spacer()
                    if shownBps > 0 {
                        Label("\(AppState.fmt(shownBps))/s",
                              systemImage: "arrow.down")
                            .labelStyle(.titleAndIcon)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.blue)
                            .transition(.opacity)
                            .accessibilityLabel(
                                "\(AppState.fmt(shownBps)) per second")
                    }
                    Text(AppState.fmt(usage?.total ?? 0))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: barFraction)
                    .progressViewStyle(.linear)
                    .tint(app.allowed ? .blue : .gray)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { if canExpand { expanded.toggle() } }
    }

    /// Blocked + filtering on.
    private var dim: Bool { choked && !app.allowed }

    /// This app's share of today's grand total.
    private var barFraction: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(usage?.total ?? 0) / Double(total))
    }
}
