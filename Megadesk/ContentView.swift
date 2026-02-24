import SwiftUI
import AppKit

struct ContentView: View {
    @State private var store = StatusStore()
    @AppStorage("megadesk.compact") private var isCompact = false
    @State private var previousApp: NSRunningApplication?

    var body: some View {
        VStack(spacing: 4) {
            if store.sessions.isEmpty {
                emptyState
            } else {
                ForEach(store.sessions) { session in
                    if isCompact {
                        CompactSessionCardView(
                            session: session,
                            tick: store.tick,
                            displayName: store.displayName(for: session),
                            onFocus: { store.focusTerminal(session: session) }
                        )
                    } else {
                        SessionCardView(
                            session: session,
                            tick: store.tick,
                            displayName: store.displayName(for: session),
                            hasCustomName: store.hasCustomName(for: session),
                            onFocus: { store.focusTerminal(session: session) },
                            onRename: { name in store.setCustomName(session: session, name: name) },
                            onEditStart: beginEditing,
                            onEditEnd: endEditing
                        )
                    }
                }
            }
            if !isCompact, let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
                Text("v\(version)  build \(build)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.2))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 2)
            }
        }
        .padding(8)
        .frame(minWidth: isCompact ? 78 : 220, maxWidth: isCompact ? 78 : 280)
    }

    private var emptyState: some View {
        Text("No active instances")
            .font(.system(size: 12))
            .foregroundColor(.white.opacity(0.4))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
    }

    // MARK: - Edit lifecycle

    private func beginEditing() {
        previousApp = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
    }

    private func endEditing() {
        previousApp?.activate()
        previousApp = nil
    }
}
