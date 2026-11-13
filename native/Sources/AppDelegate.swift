import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var view: CharacterView!
    private var state: AppState!
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        state = AppState()
        state.onQuit = { NSApp.terminate(nil) }

        guard let resourceURL = Bundle.main.resourceURL,
              let glyphs = try? GlyphSet(binURL: resourceURL.appendingPathComponent("glyphs.bin"),
                                         jsonURL: resourceURL.appendingPathComponent("glyphs.json")) else {
            fatalError("glyph atlas missing from the app bundle")
        }
        let renderer = Renderer(glyphs: glyphs, cols: 80, rows: 25)
        view = CharacterView(state: state, renderer: renderer)

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 600),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "EGA Edit"
        window.contentAspectRatio = NSSize(width: 640, height: 400)
        window.minSize = NSSize(width: 640, height: 400)
        window.backgroundColor = .black
        window.acceptsMouseMovedEvents = true
        window.contentView = view
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)

        let welcomeText = resourceURL.appendingPathComponent("WELCOME.TXT")
        if let text = try? String(contentsOf: welcomeText, encoding: .utf8) {
            state.newWindow(text: text)
            state.activeWindow?.buffer.displayTitle = "WELCOME.TXT"
        } else {
            state.newWindow()
        }

        installMenu()
        NSApp.activate(ignoringOtherApps: true)

        if let demo = ProcessInfo.processInfo.environment["EGA_UIDEMO"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                guard let self = self else { return }
                switch demo {
                case "about": self.state.dialog = Dialog.about()
                case "keys": self.state.dialog = Dialog.keys()
                case "find": self.state.dialog = Dialog.find()
                case "replace": self.state.dialog = Dialog.replace()
                case "menu": self.state.openMenu(0); self.state.menuCursor = 1
                case "context": self.state.rightClick(x: 24, y: 9)
                case "toolbar": self.state.hoverCell = (3, 1)
                default: break
                }
                self.view.needsDisplay = true
            }
        }

        if ProcessInfo.processInfo.environment["EGA_UITEST"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.runUITest()
            }
        }

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.state.cursorOn.toggle()
            self.state.updateClock(Date())
            _ = self.state.expireStatus()
            self.view.needsDisplay = true
        }
    }

    private func key(_ chars: String, code: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                         timestamp: ProcessInfo.processInfo.systemUptime,
                         windowNumber: window.windowNumber, context: nil,
                         characters: chars, charactersIgnoringModifiers: chars,
                         isARepeat: false, keyCode: code)!
    }

    private func runUITest() {
        let keys: [(String, UInt16)] = [("h", 4), ("e", 14), ("l", 37), ("l", 37), ("o", 31)]
        for (ch, code) in keys {
            view.keyDown(with: key(ch, code: code))
        }
        view.keyDown(with: key("\r", code: 36))
        view.keyDown(with: key("w", code: 13))
        view.keyDown(with: key("\u{F708}", code: 109)) // F10
        print("UITEST buffer=[\(state.activeWindow?.buffer.text() ?? "nil")] menu=\(String(describing: state.menuOpen))")
        NSApp.terminate(nil)
    }

    private func installMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        let about = NSMenuItem(title: "About EGA Edit",
                               action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        appMenu.addItem(about)
        appMenu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit EGA Edit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        appMenu.addItem(quit)
        appItem.submenu = appMenu
        NSApp.mainMenu = main
    }

    @objc private func showAbout() {
        state.dialog = Dialog.about()
        view.needsDisplay = true
    }

    @objc private func quit() {
        state.requestQuit()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        state.requestQuit()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
