import SwiftUI
import AppKit

struct AppRow: View {
    let app: AppEntry
    let usage: UsageCounter?
    let rate: (inBps: UInt64, outBps: UInt64)?
    /// Today's grand total — the per-app bar is a share of this.
    let total: UInt64
    /// Filtering is on; only then do blocked apps de-emphasize.
    let choked: Bool
    let onToggle: (Bool) -> Void

    // The live-rate label lingers briefly after traffic stops so a quick
    // burst doesn't just flicker. Parent re-renders ~1/s, which lets the
    // timed clear fire on schedule.
    @State private var shownBps: UInt64 = 0
    @State private var clearTask: Task<Void, Never>?

    private var icon: NSImage {
        guard !app.path.isEmpty else {
            return NSWorkspace.shared.icon(for: .applicationBundle)
        }
        // Walk to the .app bundle for a proper icon.
        var url = URL(fileURLWithPath: app.path)
        while url.pathComponents.count > 1 && url.pathExtension != "app" {
            url.deleteLastPathComponent()
        }
        return NSWorkspace.shared.icon(forFile:
            url.pathExtension == "app" ? url.path : app.path)
    }

    private var maxBytes: UInt64 { 1 }

    var body: some View {
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
        // Blocked apps only recede once filtering is actually on.
        .opacity(dim ? 0.7 : 1)
        .animation(.easeOut(duration: 0.6), value: shownBps)
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

    /// Blocked + filtering on.
    private var dim: Bool { choked && !app.allowed }

    /// Each app's bar is its share of today's grand total.
    private var barFraction: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(usage?.total ?? 0) / Double(total))
    }
}
