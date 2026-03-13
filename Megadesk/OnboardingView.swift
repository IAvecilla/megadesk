import AppKit
import SwiftUI

struct OnboardingView: View {
    var onFinish: () -> Void

    @State private var hookDone = HookInstaller.isInstalled()
    @State private var itermState: TerminalPermissionState = .unknown
    @State private var ghosttyState: TerminalPermissionState = .unknown

    fileprivate enum TerminalPermissionState {
        case unknown, granted, denied, notRunning
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 64, height: 64)
                }
                Text("Welcome to Megadesk")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Two quick steps to get started")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Step 1: Install hook
            StepCard(
                number: 1,
                title: "Connect Claude Code",
                description: "Adds a hook to ~/.claude/settings.json to track session activity.",
                buttonLabel: "Install Hook",
                isDone: hookDone,
                isDisabled: false
            ) {
                do {
                    try HookInstaller.install()
                    hookDone = true
                } catch {
                    // silently ignore; user can retry
                }
            }

            // Step 2: Terminal AppleScript permissions
            TerminalPermissionCard(
                number: 2,
                isDisabled: !hookDone,
                itermState: $itermState,
                ghosttyState: $ghosttyState
            )

            Button("Continue") {
                UserDefaults.standard.set(true, forKey: "megadesk.onboardingComplete")
                onFinish()
            }
            .disabled(!hookDone)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
        .frame(width: 360)
    }
}

// MARK: - Terminal Permission Card

private struct TerminalPermissionCard: View {
    let number: Int
    let isDisabled: Bool
    @Binding var itermState: OnboardingView.TerminalPermissionState
    @Binding var ghosttyState: OnboardingView.TerminalPermissionState

    var body: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 12) {
                Text("\(number)")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(isDisabled ? Color.secondary : Color.accentColor)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 6) {
                    Text("Allow Terminal Control")
                        .font(.headline)
                    Text("Grant access to each terminal you use. Megadesk uses AppleScript to focus the right tab when you click a session card.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 6) {
                        terminalRow(name: "iTerm2", state: itermState) {
                            itermState = requestPermission(
                                bundleId: "com.googlecode.iterm2",
                                scriptName: "iTerm2"
                            )
                        }
                        terminalRow(name: "Ghostty", state: ghosttyState) {
                            ghosttyState = requestPermission(
                                bundleId: "com.mitchellh.ghostty",
                                scriptName: "Ghostty"
                            )
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(4)
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
    }

    @ViewBuilder
    private func terminalRow(
        name: String,
        state: OnboardingView.TerminalPermissionState,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(name)
                .font(.callout)
            Spacer()
            switch state {
            case .granted:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .imageScale(.large)
            case .denied:
                HStack(spacing: 6) {
                    Text("Denied")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Retry", action: action)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            case .notRunning:
                HStack(spacing: 6) {
                    Text("Not running")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Retry", action: action)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            case .unknown:
                Button("Grant Access", action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private func requestPermission(bundleId: String, scriptName: String) -> OnboardingView.TerminalPermissionState {
        let running = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bundleId
        }
        guard running else { return .notRunning }

        var error: NSDictionary?
        NSAppleScript(source: "tell application \"\(scriptName)\" to get name")?
            .executeAndReturnError(&error)
        return error == nil ? .granted : .denied
    }
}

private struct StepCard: View {
    let number: Int
    let title: String
    let description: String
    let buttonLabel: String
    let isDone: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 12) {
                Text("\(number)")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(isDisabled ? Color.secondary : Color.accentColor)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer()
                        if isDone {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .imageScale(.large)
                        } else {
                            Button(buttonLabel, action: action)
                                .buttonStyle(.bordered)
                                .disabled(isDisabled)
                        }
                    }
                }
            }
            .padding(4)
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
    }
}
