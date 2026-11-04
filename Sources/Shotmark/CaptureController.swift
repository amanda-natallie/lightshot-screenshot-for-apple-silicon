import AppKit

/// Owns one overlay window per display for the duration of a capture session.
@MainActor
final class CaptureController {
    /// Above the menu bar and status items, below pop-up menus (so the color menu still shows).
    static let overlayLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)

    private var windows: [OverlayWindow] = []
    private var starting = false

    var isActive: Bool { starting || !windows.isEmpty }

    func start() {
        guard !isActive else { return }
        guard ScreenCapturer.hasPermission else {
            ScreenCapturer.requestPermission()
            showPermissionAlert()
            return
        }
        starting = true
        Task { @MainActor in
            defer { starting = false }
            do {
                let shots = try await ScreenCapturer.captureAllScreens()
                present(shots)
            } catch {
                NSApp.activate()
                NSAlert(error: error).runModal()
            }
        }
    }

    private func present(_ shots: [CapturedScreen]) {
        windows = shots.map { OverlayWindow(capture: $0, controller: self) }
        NSApp.activate()
        let mouse = NSEvent.mouseLocation
        let keyWindow = windows.first { $0.frame.contains(mouse) } ?? windows.first
        windows.forEach { $0.orderFrontRegardless() }
        keyWindow?.makeKeyAndOrderFront(nil)
        keyWindow?.makeFirstResponder(keyWindow?.overlayView)
        NSCursor.crosshair.set()
    }

    /// Only one display can hold a selection at a time.
    func selectionBegan(in view: OverlayView) {
        for w in windows where w.overlayView !== view { w.overlayView.reset() }
    }

    /// Lowers overlays so system panels (save dialog) can appear above them.
    func setOverlaysLowered(_ lowered: Bool) {
        windows.forEach { $0.level = lowered ? .normal : Self.overlayLevel }
    }

    func finish() {
        NSColorPanel.shared.orderOut(nil)
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        NSCursor.arrow.set()
    }

    private func showPermissionAlert() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Permissão de Gravação de Tela necessária"
        alert.informativeText = "Ative o \(AppInfo.name) em Ajustes do Sistema › Privacidade e Segurança › Gravação de Tela e Áudio do Sistema. O macOS só aplica a permissão depois que o app reabre — use \"Reabrir \(AppInfo.name)\" depois de ativar."
        alert.addButton(withTitle: "Abrir Ajustes")
        alert.addButton(withTitle: "Reabrir \(AppInfo.name)")
        alert.addButton(withTitle: "Cancelar")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        case .alertSecondButtonReturn:
            Self.relaunch()
        default:
            break
        }
    }

    /// Screen-capture permission is read once per process, so a grant only takes effect after a relaunch.
    static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }
}

final class OverlayWindow: NSWindow {
    let overlayView: OverlayView

    init(capture: CapturedScreen, controller: CaptureController) {
        let frame = capture.screen.frame
        let bounds = NSRect(origin: .zero, size: frame.size)
        overlayView = OverlayView(frame: bounds, image: capture.image, controller: controller)
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = CaptureController.overlayLevel
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let background = FrozenScreenView(frame: bounds, image: capture.image)
        overlayView.autoresizingMask = [.width, .height]
        background.addSubview(overlayView)
        contentView = background
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Shows the frozen screenshot as layer contents (GPU-composited, so redrawing the overlay on every drag stays cheap).
final class FrozenScreenView: NSView {
    private let image: CGImage

    init(frame: NSRect, image: CGImage) {
        self.image = image
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.contents = image
        layer?.contentsGravity = .resize
    }
}
