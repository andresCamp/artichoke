import SwiftUI
import AppKit

struct AppRow: View {
    let app: AppEntry
    let mode: ViewMode
    let usage: UsageCounter?
    let rate: (inBps: UInt64, outBps: UInt64)?
    let onToggle: (Bool) -> Void

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

            Image(nsImage: icon).resizable()
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(app.name).lineLimit(1)
                        .foregroundStyle(app.allowed ? .primary : .secondary)
                    Spacer()
                    if mode == .live {
                        Text("↓ \(AppState.fmt(rate?.inBps ?? 0))/s")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        Text(AppState.fmt(usage?.total ?? 0))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                ProgressView(value: barFraction)
                    .progressViewStyle(.linear)
                    .tint(app.allowed ? .blue : .gray)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .opacity(app.allowed ? 1 : 0.55)
    }

    /// Bar is relative to a soft 50 MB ceiling so small apps stay visible.
    private var barFraction: Double {
        let t = Double(usage?.total ?? 0)
        return min(1, t / (50 * 1_000_000))
    }
}
