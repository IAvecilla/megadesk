import AppKit
import SwiftUI
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: FloatingWindowController?
    private var statusItem: NSStatusItem?
    private var onboardingController: OnboardingWindowController?
    private var hotKeyRef: EventHotKeyRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Terminate any previously running instance before setting up.
        if let bundleID = Bundle.main.bundleIdentifier {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0 != NSRunningApplication.current }
                .forEach { $0.terminate() }
        }

        let contentView = ContentView()
        windowController = FloatingWindowController(contentView: contentView)
        windowController?.window?.delegate = self
        setupMenuBar()
        registerGlobalHotKey()

        if UserDefaults.standard.bool(forKey: "megadesk.onboardingComplete") {
            windowController?.show()
        } else {
            onboardingController = OnboardingWindowController {
                self.onboardingController = nil
                self.windowController?.show()
            }
            onboardingController?.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Global hotkey (⌘⇧M)

    private func registerGlobalHotKey() {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = 0x4d47444b  // 'MGDK'
        hotKeyID.id = 1

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let ptr = userData else { return noErr }
                DispatchQueue.main.async {
                    Unmanaged<AppDelegate>.fromOpaque(ptr).takeUnretainedValue().windowController?.toggle()
                }
                return noErr
            },
            1,
            &eventSpec,
            selfPtr,
            nil
        )

        RegisterEventHotKey(
            UInt32(kVK_ANSI_M),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            OptionBits(0),
            &hotKeyRef
        )
    }

    // MARK: - Menu bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            let icon = NSImage(named: "MenuBarIcon")
            icon?.size = NSSize(width: 18, height: 18)
            icon?.isTemplate = true
            button.image = icon
        }
        let menu = NSMenu()
        menu.delegate = self
        let toggleItem = menu.addItem(withTitle: "Hide Widget", action: #selector(toggleWidget), keyEquivalent: "M")
        toggleItem.target = self
        let compactItem = NSMenuItem(title: "Compact Mode", action: #selector(toggleCompact), keyEquivalent: "")
        compactItem.target = self
        menu.addItem(compactItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Megadesk", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem?.menu = menu
    }

    @objc private func toggleWidget() {
        windowController?.toggle()
    }

    @objc private func toggleCompact() {
        windowController?.toggleCompact()
    }
}

// MARK: - NSMenuDelegate — refresh title before menu appears

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        let isVisible = windowController?.isWidgetVisible ?? false
        menu.item(at: 0)?.title = isVisible ? "Hide Widget" : "Show Widget"
        menu.item(at: 1)?.state = (windowController?.isCompact ?? false) ? .on : .off
    }
}

// MARK: - NSWindowDelegate — close button hides instead of quitting

extension AppDelegate: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        windowController?.hide()
        return false
    }
}
