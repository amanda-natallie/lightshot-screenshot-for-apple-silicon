import AppKit
import ShotmarkCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let capture = CaptureController()
    private var hotKey: HotKey!
    private var preferences: PreferencesWindowController?
    private var captureMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: AppInfo.name)
        icon?.isTemplate = true
        statusItem.button?.image = icon
        buildMenu()

        hotKey = HotKey { [weak self] in self?.capture.start() }
        if !hotKey.register(Settings.hotKey) {
            NSLog("Shotmark: could not register hotkey \(Settings.hotKey.displayString)")
        }
        refreshMenu()

        // Ask once up front so the first capture isn't the moment the system prompt appears.
        if !ScreenCapturer.hasPermission { ScreenCapturer.requestPermission() }
    }

    private func buildMenu() {
        let menu = NSMenu()
        captureMenuItem = NSMenuItem(title: "", action: #selector(captureFromMenu), keyEquivalent: "")
        captureMenuItem.target = self
        menu.addItem(captureMenuItem)
        menu.addItem(.separator())
        let prefs = NSMenuItem(title: "Preferências…", action: #selector(openPreferences), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Sair do \(AppInfo.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func refreshMenu() {
        captureMenuItem.title = "Capturar tela   \(Settings.hotKey.displayString)"
    }

    @objc private func captureFromMenu() {
        // Let the menu finish fading out so it isn't in the screenshot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.capture.start() }
    }

    @objc private func openPreferences() {
        if preferences == nil {
            preferences = PreferencesWindowController(
                applyHotKey: { [weak self] combo in
                    let ok = self?.hotKey.register(combo) ?? false
                    if ok { DispatchQueue.main.async { self?.refreshMenu() } }
                    return ok
                },
                pauseHotKey: { [weak self] paused in
                    guard let self else { return }
                    if paused { hotKey.unregister() } else { hotKey.register(Settings.hotKey) }
                }
            )
        }
        NSApp.activate()
        preferences?.showWindow(nil)
        preferences?.window?.makeKeyAndOrderFront(nil)
    }
}
