import AppKit
import ServiceManagement
import ShotmarkCore

@MainActor
final class PreferencesWindowController: NSWindowController {
    private let recorder: ShortcutRecorder

    /// `applyHotKey` returns false when the system refuses the shortcut (already taken).
    init(applyHotKey: @escaping (KeyCombo) -> Bool, pauseHotKey: @escaping (Bool) -> Void) {
        recorder = ShortcutRecorder(combo: Settings.hotKey)
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Preferências do \(AppInfo.name)"
        window.isReleasedWhenClosed = false
        super.init(window: window)

        recorder.onRecordingChanged = pauseHotKey
        recorder.onChange = { [weak self] combo in
            if applyHotKey(combo) {
                Settings.hotKey = combo
            } else {
                _ = applyHotKey(Settings.hotKey)
                self?.recorder.combo = Settings.hotKey
                let alert = NSAlert()
                alert.messageText = "Atalho indisponível"
                alert.informativeText = "\(combo.displayString) já está em uso por outro app. Escolha outro."
                alert.runModal()
            }
        }

        let retina = NSButton(checkboxWithTitle: "Salvar em resolução Retina (pixels reais da tela)", target: self, action: #selector(toggleRetina(_:)))
        retina.state = Settings.saveRetina ? .on : .off
        let login = NSButton(checkboxWithTitle: "Abrir ao iniciar sessão", target: self, action: #selector(toggleLogin(_:)))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off

        let row = NSStackView(views: [NSTextField(labelWithString: "Atalho para capturar:"), recorder])
        row.spacing = 10
        let hint = NSTextField(labelWithString: "Clique no atalho e pressione a nova combinação. Esc cancela.")
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [row, hint, retina, login])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        window.contentView = stack
        window.setContentSize(stack.fittingSize)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    @objc private func toggleRetina(_ sender: NSButton) {
        Settings.saveRetina = sender.state == .on
    }

    @objc private func toggleLogin(_ sender: NSButton) {
        do {
            if sender.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
            NSAlert(error: error).runModal()
        }
    }
}

/// Click, then press a key combination to record a new global shortcut.
@MainActor
final class ShortcutRecorder: NSButton {
    var combo: KeyCombo { didSet { refreshTitle() } }
    var onChange: ((KeyCombo) -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?

    private var isRecording = false {
        didSet {
            guard oldValue != isRecording else { return }
            refreshTitle()
            onRecordingChanged?(isRecording)
        }
    }

    init(combo: KeyCombo) {
        self.combo = combo
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        action = #selector(startRecording)
        widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        refreshTitle()
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override var acceptsFirstResponder: Bool { true }

    @objc private func startRecording() {
        isRecording = true
        window?.makeFirstResponder(self)
    }

    override func performKeyEquivalent(with e: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: e) }
        record(e)
        return true
    }

    override func keyDown(with e: NSEvent) {
        guard isRecording else { super.keyDown(with: e); return }
        record(e)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    private func record(_ e: NSEvent) {
        if Int(e.keyCode) == 53 { isRecording = false; return } // Esc
        let chars = e.characters(byApplyingModifiers: [])
        guard let c = KeyCombo(keyCode: e.keyCode, flags: e.modifierFlags, characters: chars), c.isValidGlobal else {
            NSSound.beep()
            return
        }
        isRecording = false
        combo = c
        onChange?(c)
    }

    private func refreshTitle() {
        title = isRecording ? "Pressione o atalho…" : combo.displayString
    }
}
