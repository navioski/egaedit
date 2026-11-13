import Foundation
import AppKit

struct KeyEvent {
    var keyCode: UInt16
    var chars: String
    var shift: Bool
    var option: Bool
    var command: Bool
    var control: Bool
}

enum Cmd {
    case new, open, save, saveAs, quit
    case undo, cut, copy, paste, selectAll
    case find, replace, findNext
    case insertMode
    case nextWindow, closeWindow, zoomWindow, cascade, tile
    case about, keys
    case menu
    case openRecent(Int)
}

struct MenuItemSpec {
    let label: String
    let shortcut: String
    let cmd: Cmd?
    let separator: Bool
    var enabled = true
}

final class EditorWindow {
    var rect: CellRect
    var savedRect: CellRect?
    var zoomed = false
    let buffer: TextBuffer

    init(rect: CellRect, buffer: TextBuffer) {
        self.rect = rect
        self.buffer = buffer
    }
}

enum CursorKind {
    case arrow, ibeam, hand, resize
}

final class ContextMenu {
    let items: [MenuItemSpec]
    let rect: CellRect
    var cursor: Int

    init(items: [MenuItemSpec], rect: CellRect, cursor: Int) {
        self.items = items
        self.rect = rect
        self.cursor = cursor
    }
}

final class AppState {
    static let cols = 80
    static let rows = 25
    static let menuRow = 0
    static let toolbarRow = 1
    static let desktopTop = 2
    static let statusRow = 24

    var windows: [EditorWindow] = []
    var dialog: Dialog?
    var menuOpen: Int?
    var menuCursor = 0
    private var contextMenu: ContextMenu?
    var statusText: String?
    var statusUntil: Date?
    var cursorOn = true
    var clockText = "00:00:00"
    var lastSearch = ""
    var onQuit: (() -> Void)?

    private var pendingClose: Int?
    private var quitQueue: [Int] = []
    private var dragState: (index: Int, dx: Int, dy: Int)?
    private var textDrag = false
    private var scrollDrag: (window: Int, vertical: Bool, offset: Int)?
    private var resizeDrag: Int?
    private var openCount = 0
    private var recentPaths: [String] = UserDefaults.standard.stringArray(forKey: "egaedit.recent") ?? []
    var hoverCell: (x: Int, y: Int)?
    private var scrollRemainderY: Double = 0
    private var scrollRemainderX: Double = 0
    var isContextMenuOpen: Bool { contextMenu != nil }

    // MARK: - Windows

    var activeWindow: EditorWindow? { windows.last }

    static func baseRect(step: Int) -> CellRect {
        let s = max(0, min(step, 3))
        return CellRect(x: 2 + 2 * s, y: 3 + s, w: 76 - 4 * s, h: 20 - 2 * s)
    }

    static func textArea(_ frame: CellRect) -> CellRect {
        CellRect(x: frame.x + 1, y: frame.y + 1, w: frame.w - 3, h: frame.h - 2)
    }

    func newWindow(fileURL: URL? = nil, text: String? = nil) {
        let buffer: TextBuffer
        if let url = fileURL {
            let content = (try? String(contentsOf: url, encoding: .utf8))
                ?? (try? String(contentsOf: url, encoding: .isoLatin1))
                ?? ""
            buffer = TextBuffer(text: content, url: url)
            addRecent(url)
        } else {
            buffer = TextBuffer(text: text ?? "", url: nil)
        }
        openCount += 1
        let window = EditorWindow(rect: AppState.baseRect(step: openCount - 1), buffer: buffer)
        windows.append(window)
    }

    func bringToFront(_ index: Int) {
        guard index >= 0 && index < windows.count else { return }
        let w = windows.remove(at: index)
        windows.append(w)
    }

    func removeWindow(_ index: Int) {
        guard index >= 0 && index < windows.count else { return }
        windows.remove(at: index)
        dialog = nil
        pendingClose = nil
        dragState = nil
    }

    func closeWindow(_ index: Int) {
        guard index >= 0 && index < windows.count else { return }
        let w = windows[index]
        if w.buffer.modified {
            pendingClose = index
            dialog = Dialog.savePrompt(name: w.buffer.title, index: index)
        } else {
            removeWindow(index)
        }
    }

    func requestQuit() {
        quitQueue = windows.indices.filter { windows[$0].buffer.modified }
        if quitQueue.isEmpty {
            onQuit?()
        } else {
            showQuitPrompt()
        }
    }

    private func showQuitPrompt() {
        guard let idx = quitQueue.first, idx < windows.count else {
            onQuit?()
            return
        }
        dialog = Dialog.savePrompt(name: windows[idx].buffer.title, index: idx)
    }

    // MARK: - Files

    func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Open File"
        if panel.runModal() == .OK, let url = panel.url {
            newWindow(fileURL: url)
            setStatus("Opened \(url.lastPathComponent)")
        }
    }

    @discardableResult
    func saveWindow(_ index: Int) -> Bool {
        guard index >= 0 && index < windows.count else { return false }
        let buffer = windows[index].buffer
        if buffer.fileURL == nil {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "Untitled.txt"
            panel.title = "Save File As"
            guard panel.runModal() == .OK, let url = panel.url else { return false }
            if buffer.save(to: url) {
                setStatus("Saved \(url.lastPathComponent)")
                return true
            }
            return false
        }
        if buffer.save() {
            setStatus("Saved \(buffer.title)")
            return true
        }
        return false
    }

    func saveActive() {
        guard let w = activeWindow else { return }
        if w.buffer.fileURL == nil {
            saveWindow(windows.count - 1)
        } else {
            _ = saveWindow(windows.count - 1)
        }
    }

    func saveActiveAs() {
        guard let w = activeWindow else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = w.buffer.fileURL?.lastPathComponent ?? "Untitled.txt"
        panel.title = "Save File As"
        if panel.runModal() == .OK, let url = panel.url {
            if w.buffer.save(to: url) {
                addRecent(url)
                setStatus("Saved \(url.lastPathComponent)")
            }
        }
    }

    // MARK: - Commands

    func isEnabled(_ cmd: Cmd) -> Bool {
        switch cmd {
        case .save, .saveAs, .closeWindow, .zoomWindow:
            return !windows.isEmpty
        case .undo:
            return activeWindow?.buffer.canUndo ?? false
        case .cut, .copy:
            return activeWindow?.buffer.hasSelection ?? false
        case .paste:
            return NSPasteboard.general.string(forType: .string) != nil
        case .selectAll:
            return activeWindow != nil
        case .nextWindow:
            return windows.count > 1
        case .cascade, .tile:
            return windows.count > 1
        case .insertMode:
            return activeWindow != nil
        default:
            return true
        }
    }

    func perform(_ cmd: Cmd) {
        menuOpen = nil
        switch cmd {
        case .new:
            newWindow()
        case .open:
            openPanel()
        case .save:
            saveActive()
        case .saveAs:
            saveActiveAs()
        case .quit:
            requestQuit()
        case .undo:
            activeWindow?.buffer.undo()
        case .cut:
            copySelection()
            activeWindow?.buffer.deleteSelection()
        case .copy:
            copySelection()
        case .paste:
            pasteClipboard()
        case .selectAll:
            activeWindow?.buffer.selectAll()
        case .find:
            dialog = Dialog.find()
        case .replace:
            dialog = Dialog.replace()
        case .findNext:
            if !lastSearch.isEmpty { performFind(lastSearch) }
        case .insertMode:
            if let b = activeWindow?.buffer {
                b.overwrite.toggle()
                setStatus(b.overwrite ? "Overwrite mode" : "Insert mode")
            }
        case .nextWindow:
            if windows.count > 1 {
                let w = windows.removeFirst()
                windows.append(w)
            }
        case .closeWindow:
            closeWindow(windows.count - 1)
        case .zoomWindow:
            guard let w = activeWindow else { return }
            if w.zoomed, let saved = w.savedRect {
                w.rect = saved
                w.zoomed = false
            } else {
                w.savedRect = w.rect
                w.rect = CellRect(x: 1, y: 2, w: 78, h: 22)
                w.zoomed = true
            }
        case .cascade:
            for (i, w) in windows.enumerated() {
                w.rect = AppState.baseRect(step: i)
                w.zoomed = false
            }
        case .tile:
            let n = max(1, windows.count)
            let width = max(24, 80 / n)
            for (i, w) in windows.enumerated() {
                w.rect = CellRect(x: i * width, y: 1, w: width, h: 23)
                w.zoomed = false
            }
        case .about:
            dialog = Dialog.about()
        case .keys:
            dialog = Dialog.keys()
        case .menu:
            openMenu(0)
        case .openRecent(let index):
            openRecent(index)
        }
    }

    func copySelection() {
        guard let w = activeWindow else { return }
        let text = w.buffer.selectedText()
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        setStatus("Copied \(text.count) character(s)")
    }

    func pasteClipboard() {
        guard let raw = NSPasteboard.general.string(forType: .string) else { return }
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n")
        activeWindow?.buffer.insert(text)
    }

    func performFind(_ query: String) {
        lastSearch = query
        guard let w = activeWindow else { return }
        if !w.buffer.find(query) {
            dialog = Dialog.message("Search string not found.")
        }
    }

    func setStatus(_ text: String) {
        statusText = text
        statusUntil = Date().addingTimeInterval(3)
    }

    func updateClock(_ date: Date) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        let text = f.string(from: date)
        if text != clockText { clockText = text }
    }

    func expireStatus(now: Date = Date()) -> Bool {
        if let until = statusUntil, now >= until {
            statusText = nil
            statusUntil = nil
            return true
        }
        return false
    }

    // MARK: - Dialog results

    func handleDialogAction(_ action: DialogAction) {
        guard let d = dialog else { return }
        switch d.kind {
        case .about, .keys, .message:
            dialog = nil

        case .find:
            let query = d.inputs.first?.text ?? ""
            dialog = nil
            if action == .find && !query.isEmpty {
                performFind(query)
            }

        case .replace:
            let find = d.inputs.first?.text ?? ""
            let replacement = d.inputs.count > 1 ? d.inputs[1].text : ""
            dialog = nil
            if action == .replaceAll && !find.isEmpty {
                guard let w = activeWindow else { return }
                let n = w.buffer.replaceAll(find, with: replacement)
                setStatus(n > 0 ? "\(n) replacement(s)" : "No match")
            }

        case .savePrompt(let idx):
            if let close = pendingClose {
                switch action {
                case .yes:
                    if saveWindow(close) {
                        pendingClose = nil
                        removeWindow(close)
                    } else {
                        pendingClose = nil
                        dialog = nil
                    }
                case .no:
                    pendingClose = nil
                    removeWindow(close)
                default:
                    pendingClose = nil
                    dialog = nil
                }
                return
            }
            switch action {
            case .yes:
                if saveWindow(idx) {
                    quitQueue.removeAll { $0 == idx }
                    dialog = nil
                    showQuitPrompt()
                } else {
                    quitQueue = []
                    dialog = nil
                }
            case .no:
                if idx < windows.count { windows[idx].buffer.modified = false }
                quitQueue.removeAll { $0 == idx }
                dialog = nil
                showQuitPrompt()
            default:
                quitQueue = []
                dialog = nil
            }
        }
    }

    // MARK: - Menus

    static let menuTitles = ["File", "Edit", "Search", "Options", "Window", "Help"]

    func menuSpecs() -> [[MenuItemSpec]] {
        let hasWindow = !windows.isEmpty
        let hasSelection = activeWindow?.buffer.hasSelection ?? false
        let canUndo = activeWindow?.buffer.canUndo ?? false
        let overwrite = activeWindow?.buffer.overwrite ?? false

        var file: [MenuItemSpec] = [
            MenuItemSpec(label: "~N~ew", shortcut: "Cmd-N", cmd: .new, separator: false),
            MenuItemSpec(label: "~O~pen...", shortcut: "Cmd-O", cmd: .open, separator: false),
            MenuItemSpec(label: "~S~ave", shortcut: "Cmd-S", cmd: .save, separator: false, enabled: hasWindow),
            MenuItemSpec(label: "Save ~a~s...", shortcut: "Cmd-Shift-S", cmd: .saveAs, separator: false, enabled: hasWindow),
        ]
        if !recentPaths.isEmpty {
            file.append(MenuItemSpec(label: "", shortcut: "", cmd: nil, separator: true))
            for (i, path) in recentPaths.enumerated() {
                let name = URL(fileURLWithPath: path).lastPathComponent
                file.append(MenuItemSpec(label: "\(i + 1)  \(name)", shortcut: "",
                                         cmd: .openRecent(i), separator: false,
                                         enabled: FileManager.default.fileExists(atPath: path)))
            }
        }
        file.append(MenuItemSpec(label: "", shortcut: "", cmd: nil, separator: true))
        file.append(MenuItemSpec(label: "~Q~uit", shortcut: "Cmd-Q", cmd: .quit, separator: false))
        let edit: [MenuItemSpec] = [
            MenuItemSpec(label: "~U~ndo", shortcut: "Cmd-Z", cmd: .undo, separator: false, enabled: canUndo),
            MenuItemSpec(label: "", shortcut: "", cmd: nil, separator: true),
            MenuItemSpec(label: "Cu~t~", shortcut: "Cmd-X", cmd: .cut, separator: false, enabled: hasSelection),
            MenuItemSpec(label: "~C~opy", shortcut: "Cmd-C", cmd: .copy, separator: false, enabled: hasSelection),
            MenuItemSpec(label: "~P~aste", shortcut: "Cmd-V", cmd: .paste, separator: false),
            MenuItemSpec(label: "", shortcut: "", cmd: nil, separator: true),
            MenuItemSpec(label: "Select ~A~ll", shortcut: "Cmd-A", cmd: .selectAll, separator: false, enabled: hasWindow),
        ]
        let search: [MenuItemSpec] = [
            MenuItemSpec(label: "~F~ind...", shortcut: "Cmd-F", cmd: .find, separator: false),
            MenuItemSpec(label: "~R~eplace...", shortcut: "Cmd-R", cmd: .replace, separator: false),
            MenuItemSpec(label: "Find ~N~ext", shortcut: "Cmd-G", cmd: .findNext, separator: false),
        ]
        let options: [MenuItemSpec] = [
            MenuItemSpec(label: (overwrite ? "· " : "  ") + "~I~nsert mode",
                         shortcut: "", cmd: .insertMode, separator: false, enabled: hasWindow),
        ]
        let window: [MenuItemSpec] = [
            MenuItemSpec(label: "~N~ext", shortcut: "F6", cmd: .nextWindow, separator: false),
            MenuItemSpec(label: "~C~lose", shortcut: "Cmd-W", cmd: .closeWindow, separator: false, enabled: hasWindow),
            MenuItemSpec(label: "", shortcut: "", cmd: nil, separator: true),
            MenuItemSpec(label: "Casc~a~de", shortcut: "", cmd: .cascade, separator: false),
            MenuItemSpec(label: "~T~ile", shortcut: "", cmd: .tile, separator: false),
            MenuItemSpec(label: "~Z~oom", shortcut: "F5", cmd: .zoomWindow, separator: false, enabled: hasWindow),
        ]
        let help: [MenuItemSpec] = [
            MenuItemSpec(label: "~K~eyboard", shortcut: "F1", cmd: .keys, separator: false),
            MenuItemSpec(label: "~A~bout...", shortcut: "", cmd: .about, separator: false),
        ]
        return [file, edit, search, options, window, help]
    }

    static func displayWidth(_ label: String) -> Int {
        label.reduce(0) { $0 + ($1 == "~" ? 0 : 1) }
    }

    func menuBarPlacements() -> [(x: Int, w: Int)] {
        var x = 1
        var out: [(Int, Int)] = []
        for title in AppState.menuTitles {
            let w = title.count + 2
            out.append((x, w))
            x += w
        }
        return out
    }

    func menuIndex(atX x: Int) -> Int? {
        for (i, p) in menuBarPlacements().enumerated() where x >= p.x && x < p.x + p.w {
            return i
        }
        return nil
    }

    func menuIndex(forHot ch: Character) -> Int? {
        let lower = Character(ch.lowercased())
        for (i, title) in AppState.menuTitles.enumerated() {
            if title.first.map({ Character($0.lowercased()) }) == lower { return i }
        }
        return nil
    }

    func menuGeometry(_ index: Int) -> CellRect {
        let specs = menuSpecs()[index]
        var width = 20
        for item in specs {
            width = max(width, AppState.displayWidth(item.label) + item.shortcut.count + 6)
        }
        let placements = menuBarPlacements()
        let x = min(placements[index].x, 79 - width)
        return CellRect(x: max(0, x), y: 1, w: width, h: specs.count + 2)
    }

    func firstSelectable(_ index: Int) -> Int {
        let specs = menuSpecs()[index]
        return specs.firstIndex { !$0.separator } ?? 0
    }

    func moveMenuCursor(_ delta: Int) {
        guard let open = menuOpen else { return }
        let specs = menuSpecs()[open]
        guard !specs.isEmpty else { return }
        var i = menuCursor
        for _ in 0..<specs.count {
            i = (i + delta + specs.count) % specs.count
            if !specs[i].separator { menuCursor = i; return }
        }
    }

    func openMenu(_ index: Int) {
        menuOpen = index
        menuCursor = firstSelectable(index)
    }

    func switchMenu(_ delta: Int) {
        guard let open = menuOpen else { return }
        let n = AppState.menuTitles.count
        openMenu((open + delta + n) % n)
    }

    func executeMenuItem(_ menuIndex: Int, _ itemIndex: Int) {
        let specs = menuSpecs()[menuIndex]
        guard itemIndex >= 0 && itemIndex < specs.count else { return }
        let item = specs[itemIndex]
        guard !item.separator, let cmd = item.cmd, item.enabled else { return }
        menuOpen = nil
        perform(cmd)
    }


    // MARK: - Toolbar, status bar, scrollbars, recents

    private struct ToolButton {
        let title: String
        let cmd: Cmd
        let rect: CellRect
    }

    private func toolButtons() -> [ToolButton] {
        let groups: [[(String, Cmd)]] = [
            [("New", .new), ("Open", .open), ("Save", .save)],
            [("Undo", .undo)],
            [("Cut", .cut), ("Copy", .copy), ("Paste", .paste)],
            [("Find", .find)],
        ]
        var x = 1
        var out: [ToolButton] = []
        for (gi, group) in groups.enumerated() {
            if gi > 0 { x += 2 }
            for (title, cmd) in group {
                let w = title.count + 4
                out.append(ToolButton(title: title, cmd: cmd,
                                      rect: CellRect(x: x, y: AppState.toolbarRow, w: w, h: 1)))
                x += w + 1
            }
        }
        return out
    }

    private func toolButton(atX x: Int) -> ToolButton? {
        toolButtons().first { x >= $0.rect.x && x < $0.rect.x + $0.rect.w }
    }

    private struct StatusSeg {
        let x: Int
        let w: Int
        let hot: String
        let rest: String
        let cmd: Cmd
    }

    private func statusSegments() -> [StatusSeg] {
        let items: [(String, String, Cmd)] = [
            ("F1", " Help", .keys),
            ("F2", " Save", .save),
            ("F3", " Open", .open),
            ("F4", " New", .new),
            ("F5", " Zoom", .zoomWindow),
            ("F6", " Next", .nextWindow),
            ("F10", " Menu", .menu),
        ]
        var x = 1
        var out: [StatusSeg] = []
        for (hot, rest, cmd) in items {
            out.append(StatusSeg(x: x, w: hot.count + rest.count, hot: hot, rest: rest, cmd: cmd))
            x += hot.count + rest.count + 2
        }
        return out
    }

    private func statusSegment(atX x: Int) -> StatusSeg? {
        statusSegments().first { x >= $0.x && x < $0.x + $0.w }
    }

    private struct ScrollGeom {
        let trackStart: Int
        let trackLen: Int
        let thumbStart: Int
        let thumbLen: Int
        let maxScroll: Int
    }

    private func verticalScroll(_ w: EditorWindow) -> ScrollGeom {
        let f = w.rect
        let trackStart = f.y + 2
        let trackLen = max(0, (f.maxY - 1) - trackStart)
        let total = max(1, w.buffer.lineCount)
        let maxScroll = max(1, total - w.buffer.viewHeight)
        let thumbLen = min(3, trackLen)
        let pos = min(max(0, w.buffer.scrollLine), maxScroll)
        let thumbStart = trackLen > thumbLen
            ? trackStart + (trackLen - thumbLen) * pos / maxScroll
            : trackStart
        return ScrollGeom(trackStart: trackStart, trackLen: trackLen,
                          thumbStart: thumbStart, thumbLen: thumbLen, maxScroll: maxScroll)
    }

    private func horizontalScroll(_ w: EditorWindow) -> ScrollGeom {
        let f = w.rect
        let trackStart = f.x + 15
        let trackLen = max(0, (f.maxX - 1) - trackStart)
        let longest = max(1, w.buffer.lines.map { $0.count }.max() ?? 0)
        let maxScroll = max(1, longest - w.buffer.viewWidth)
        let thumbLen = min(3, trackLen)
        let pos = min(max(0, w.buffer.scrollCol), maxScroll)
        let thumbStart = trackLen > thumbLen
            ? trackStart + (trackLen - thumbLen) * pos / maxScroll
            : trackStart
        return ScrollGeom(trackStart: trackStart, trackLen: trackLen,
                          thumbStart: thumbStart, thumbLen: thumbLen, maxScroll: maxScroll)
    }

    private func updateViewSize(_ w: EditorWindow) {
        let ta = AppState.textArea(w.rect)
        w.buffer.viewWidth = ta.w
        w.buffer.viewHeight = ta.h
    }

    private func addRecent(_ url: URL) {
        let path = url.path
        recentPaths.removeAll { $0 == path }
        recentPaths.insert(path, at: 0)
        if recentPaths.count > 5 {
            recentPaths.removeLast(recentPaths.count - 5)
        }
        UserDefaults.standard.set(recentPaths, forKey: "egaedit.recent")
    }

    func openRecent(_ index: Int) {
        guard index >= 0 && index < recentPaths.count else { return }
        let path = recentPaths[index]
        guard FileManager.default.fileExists(atPath: path) else {
            recentPaths.remove(at: index)
            UserDefaults.standard.set(recentPaths, forKey: "egaedit.recent")
            return
        }
        newWindow(fileURL: URL(fileURLWithPath: path))
    }

    // MARK: - Keyboard

    func wantsRawKey(_ key: KeyEvent) -> Bool {
        if menuOpen != nil { return true }
        if contextMenu != nil { return true }
        if dialog != nil {
            if key.command || key.control || key.option { return true }
        }
        if key.command || key.control || key.option { return true }
        switch key.keyCode {
        case 53, 36, 76, 48, 51, 117, 123, 124, 125, 126, 115, 119, 116, 121,
             122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111:
            return true
        default:
            return false
        }
    }

    func keyDown(_ key: KeyEvent) {
        if let cm = contextMenu {
            switch key.keyCode {
            case 53:
                contextMenu = nil
            case 125, 126:
                let dir = key.keyCode == 125 ? 1 : -1
                var i = cm.cursor
                for _ in 0..<cm.items.count {
                    i = (i + dir + cm.items.count) % cm.items.count
                    if !cm.items[i].separator {
                        cm.cursor = i
                        break
                    }
                }
            case 36, 76:
                let entry = cm.items[cm.cursor]
                if !entry.separator, let cmd = entry.cmd, entry.enabled {
                    contextMenu = nil
                    perform(cmd)
                }
            default:
                break
            }
            return
        }
        if let d = dialog {
            if let action = d.key(key) {
                handleDialogAction(action)
            }
            return
        }
        if menuOpen != nil {
            handleMenuKey(key)
            return
        }
        if key.command || key.control {
            if handleShortcut(key) { return }
        }
        if key.option, let ch = key.chars.first, let idx = menuIndex(forHot: ch) {
            openMenu(idx)
            return
        }
        switch key.keyCode {
        case 122: perform(.keys)
        case 120: perform(.save)
        case 99: perform(.open)
        case 118: perform(.new)
        case 96: perform(.zoomWindow)
        case 97: perform(.nextWindow)
        case 109: openMenu(0)
        case 53: menuOpen = nil
        default:
            handleEditorKey(key)
        }
    }

    func handleShortcut(_ key: KeyEvent) -> Bool {
        guard let ch = key.chars.lowercased().first else { return false }
        switch ch {
        case "n": perform(.new); return true
        case "o": perform(.open); return true
        case "s":
            if key.shift { perform(.saveAs) } else { perform(.save) }
            return true
        case "q": requestQuit(); return true
        case "w": perform(.closeWindow); return true
        case "z": perform(.undo); return true
        case "x": perform(.cut); return true
        case "c": perform(.copy); return true
        case "v": perform(.paste); return true
        case "a": perform(.selectAll); return true
        case "f": perform(.find); return true
        case "r": perform(.replace); return true
        case "g": perform(.findNext); return true
        default: return false
        }
    }

    func handleMenuKey(_ key: KeyEvent) {
        switch key.keyCode {
        case 53, 109:
            menuOpen = nil
        case 125:
            moveMenuCursor(1)
        case 126:
            moveMenuCursor(-1)
        case 123:
            switchMenu(-1)
        case 124:
            switchMenu(1)
        case 36, 76:
            if let open = menuOpen { executeMenuItem(open, menuCursor) }
        default:
            if key.option, let ch = key.chars.first, let idx = menuIndex(forHot: ch) {
                openMenu(idx)
            }
        }
    }

    func handleEditorKey(_ key: KeyEvent) {
        guard let w = activeWindow else { return }
        let b = w.buffer
        switch key.keyCode {
        case 51: b.backspace()
        case 117: b.deleteForward()
        case 36, 76: b.newline()
        case 48: b.insert("    ")
        case 123: b.moveLeft(selecting: key.shift)
        case 124: b.moveRight(selecting: key.shift)
        case 125: b.moveDown(selecting: key.shift)
        case 126: b.moveUp(selecting: key.shift)
        case 115: b.home(selecting: key.shift)
        case 119: b.end(selecting: key.shift)
        case 116: b.pageUp(selecting: key.shift)
        case 121: b.pageDown(selecting: key.shift)
        default: break
        }
    }

    func insertText(_ text: String) {
        if let d = dialog {
            d.insertText(text)
            return
        }
        guard let w = activeWindow else { return }
        w.buffer.insert(text)
    }

    // MARK: - Mouse

    func mouseDown(x: Int, y: Int, shift: Bool, clicks: Int) {
        if let d = dialog {
            if y == d.frame.y && x >= d.frame.x + 2 && x <= d.frame.x + 4 {
                handleDialogAction(.cancel)
                return
            }
            if let action = d.click(x, y) {
                handleDialogAction(action)
            }
            return
        }
        if contextMenu != nil {
            handleContextClick(x: x, y: y)
            return
        }
        if let open = menuOpen {
            if y == AppState.menuRow {
                if let idx = menuIndex(atX: x) {
                    if idx == open { menuOpen = nil } else { openMenu(idx) }
                } else {
                    menuOpen = nil
                }
                return
            }
            let geo = menuGeometry(open)
            if geo.contains(x, y) {
                executeMenuItem(open, y - geo.y - 1)
                return
            }
            menuOpen = nil
            return
        }

        if y == AppState.menuRow {
            if let idx = menuIndex(atX: x) { openMenu(idx) }
            return
        }
        if y == AppState.toolbarRow {
            if let button = toolButton(atX: x), isEnabled(button.cmd) {
                perform(button.cmd)
            }
            return
        }
        if y == AppState.statusRow {
            if let seg = statusSegment(atX: x), isEnabled(seg.cmd) {
                perform(seg.cmd)
            }
            return
        }

        for i in stride(from: windows.count - 1, through: 0, by: -1) {
            let w = windows[i]
            guard w.rect.contains(x, y) else { continue }
            bringToFront(i)
            let active = windows.count - 1
            let win = windows[active]
            let f = win.rect
            updateViewSize(win)

            if x == f.maxX && y == f.maxY {
                resizeDrag = active
                return
            }

            if y == f.y {
                if x >= f.x + 2 && x <= f.x + 4 {
                    closeWindow(active)
                } else if x >= f.maxX - 4 && x <= f.maxX - 2 {
                    perform(.zoomWindow)
                } else if clicks == 2 {
                    perform(.zoomWindow)
                } else {
                    dragState = (active, x - f.x, y - f.y)
                }
                return
            }

            let ta = AppState.textArea(f)
            if ta.contains(x, y) {
                let line = win.buffer.scrollLine + (y - ta.y)
                let col = win.buffer.scrollCol + (x - ta.x)
                if clicks >= 3 {
                    win.buffer.selectLine(line)
                } else if clicks == 2 {
                    win.buffer.selectWord(line: line, col: col)
                } else {
                    win.buffer.setCursor(line: line, col: col, selecting: shift)
                    if !shift {
                        win.buffer.anchor = (win.buffer.line, win.buffer.col)
                    }
                    textDrag = true
                }
                return
            }

            if x == f.maxX - 1 && y == f.y + 1 {
                win.buffer.scrollLine = max(0, win.buffer.scrollLine - 1)
                return
            }
            if x == f.maxX - 1 && y == f.maxY - 1 {
                win.buffer.scrollLine = min(max(0, win.buffer.lineCount - 1),
                                            win.buffer.scrollLine + 1)
                return
            }
            if x == f.maxX - 1 && y > f.y + 1 && y < f.maxY - 1 {
                let g = verticalScroll(win)
                if y >= g.thumbStart && y < g.thumbStart + g.thumbLen {
                    scrollDrag = (active, true, y - g.thumbStart)
                } else if y < g.thumbStart {
                    win.buffer.scrollLine = max(0, win.buffer.scrollLine - win.buffer.viewHeight)
                } else {
                    win.buffer.scrollLine = min(max(0, win.buffer.lineCount - 1),
                                                win.buffer.scrollLine + win.buffer.viewHeight)
                }
                return
            }

            let hs = f.x + 14
            let he = f.maxX - 1
            if y == f.maxY && x >= hs && x <= he {
                if x == hs {
                    win.buffer.scrollCol = max(0, win.buffer.scrollCol - 1)
                    return
                }
                if x == he {
                    win.buffer.scrollCol += 1
                    return
                }
                let g = horizontalScroll(win)
                if x >= g.thumbStart && x < g.thumbStart + g.thumbLen {
                    scrollDrag = (active, false, x - g.thumbStart)
                } else if x < g.thumbStart {
                    win.buffer.scrollCol = max(0, win.buffer.scrollCol - win.buffer.viewWidth)
                } else {
                    win.buffer.scrollCol += win.buffer.viewWidth
                }
                return
            }
            return
        }
    }

    func mouseDragged(x: Int, y: Int) {
        if let sd = scrollDrag, sd.window < windows.count {
            let w = windows[sd.window]
            if sd.vertical {
                let g = verticalScroll(w)
                let span = max(1, g.trackLen - g.thumbLen)
                let start = min(max(g.trackStart, y - sd.offset), g.trackStart + span)
                w.buffer.scrollLine = min(g.maxScroll,
                                          max(0, (start - g.trackStart) * g.maxScroll / span))
            } else {
                let g = horizontalScroll(w)
                let span = max(1, g.trackLen - g.thumbLen)
                let start = min(max(g.trackStart, x - sd.offset), g.trackStart + span)
                w.buffer.scrollCol = min(g.maxScroll,
                                         max(0, (start - g.trackStart) * g.maxScroll / span))
            }
            return
        }

        if let index = resizeDrag, index < windows.count {
            let w = windows[index]
            let f = w.rect
            let newW = min(80 - f.x, max(30, x - f.x + 1))
            let newH = min(24 - f.y, max(8, y - f.y + 1))
            w.rect = CellRect(x: f.x, y: f.y, w: newW, h: newH)
            w.zoomed = false
            updateViewSize(w)
            return
        }

        if textDrag, let w = windows.last {
            let ta = AppState.textArea(w.rect)
            let cx = min(max(x, ta.x), ta.maxX)
            let cy = min(max(y, ta.y), ta.maxY)
            let line = w.buffer.scrollLine + (cy - ta.y)
            let col = w.buffer.scrollCol + (cx - ta.x)
            w.buffer.setCursor(line: line, col: col, selecting: true)
            return
        }

        guard let drag = dragState, drag.index < windows.count else { return }
        let w = windows[drag.index]
        let nx = min(max(0, x - drag.dx), 80 - w.rect.w)
        let ny = min(max(AppState.desktopTop, y - drag.dy), 24 - w.rect.h)
        w.rect = CellRect(x: nx, y: ny, w: w.rect.w, h: w.rect.h)
        w.zoomed = false
    }

    func mouseUp() {
        dragState = nil
        textDrag = false
        scrollDrag = nil
        resizeDrag = nil
    }

    func mouseMoved(x: Int, y: Int) {
        hoverCell = (x, y)
        if let open = menuOpen, y == AppState.menuRow, let idx = menuIndex(atX: x), idx != open {
            openMenu(idx)
        }
        if let open = menuOpen {
            let geo = menuGeometry(open)
            if geo.contains(x, y) {
                let item = y - geo.y - 1
                let specs = menuSpecs()[open]
                if item >= 0 && item < specs.count && !specs[item].separator {
                    menuCursor = item
                }
            }
        }
        if let cm = contextMenu, cm.rect.contains(x, y) {
            let item = y - cm.rect.y - 1
            if item >= 0 && item < cm.items.count && !cm.items[item].separator {
                cm.cursor = item
            }
        }
    }

    func resetScrollAccumulators() {
        scrollRemainderY = 0
        scrollRemainderX = 0
    }

    /// dy/dx are in points for a trackpad and in "notches" for a wheel.
    /// pointsPerLine is the on-screen height of one character row.
    func scrollWheel(x: Int, y: Int, dy: Double, dx: Double,
                     precise: Bool, pointsPerLine: Double) {
        if dialog != nil || menuOpen != nil || contextMenu != nil { return }
        var target: EditorWindow?
        for i in stride(from: windows.count - 1, through: 0, by: -1)
        where windows[i].rect.contains(x, y) {
            target = windows[i]
            break
        }
        guard let w = target ?? windows.last else { return }
        updateViewSize(w)

        let perLine = precise ? max(1, pointsPerLine) : 1
        let lineFactor = precise ? (1.0 / perLine) : 3.0

        if dy != 0 {
            scrollRemainderY += dy * lineFactor
            var lines = Int(scrollRemainderY.rounded(.down))
            scrollRemainderY -= Double(lines)
            let page = max(1, w.buffer.viewHeight / 2)
            lines = min(page, max(-page, lines))
            if lines != 0 {
                let maxScroll = max(0, w.buffer.lineCount - w.buffer.viewHeight)
                w.buffer.scrollLine = min(maxScroll, max(0, w.buffer.scrollLine - lines))
            }
        }

        // Ignore the small horizontal jitter of a two-finger swipe.
        let wantsHorizontal = precise ? abs(dx) > abs(dy) * 1.5 : dx != 0
        if wantsHorizontal && dx != 0 {
            let colFactor = precise ? (1.0 / max(1, pointsPerLine / 2)) : 2.0
            scrollRemainderX += dx * colFactor
            var cols = Int(scrollRemainderX.rounded(.down))
            scrollRemainderX -= Double(cols)
            let page = max(1, w.buffer.viewWidth / 2)
            cols = min(page, max(-page, cols))
            if cols != 0 {
                let longest = w.buffer.lines.map { $0.count }.max() ?? 0
                let maxScroll = max(0, longest - w.buffer.viewWidth)
                w.buffer.scrollCol = min(maxScroll, max(0, w.buffer.scrollCol - cols))
            }
        }
    }

    func rightClick(x: Int, y: Int) {
        guard dialog == nil, menuOpen == nil else { return }
        contextMenu = nil
        for i in stride(from: windows.count - 1, through: 0, by: -1) {
            let w = windows[i]
            guard w.rect.contains(x, y) else { continue }
            bringToFront(i)
            let active = windows.count - 1
            let win = windows[active]
            updateViewSize(win)
            let ta = AppState.textArea(win.rect)
            guard ta.contains(x, y) else { return }
            let line = win.buffer.scrollLine + (y - ta.y)
            let col = win.buffer.scrollCol + (x - ta.x)
            let b = win.buffer
            let insideSelection: Bool = {
                guard let (s, e) = b.selection else { return false }
                let afterStart = line > s.0 || (line == s.0 && col >= s.1)
                let beforeEnd = line < e.0 || (line == e.0 && col < e.1)
                return afterStart && beforeEnd
            }()
            if !insideSelection {
                b.setCursor(line: line, col: col, selecting: false)
            }
            let items: [MenuItemSpec] = [
                MenuItemSpec(label: "~U~ndo", shortcut: "", cmd: .undo, separator: false, enabled: b.canUndo),
                MenuItemSpec(label: "", shortcut: "", cmd: nil, separator: true),
                MenuItemSpec(label: "Cu~t~", shortcut: "", cmd: .cut, separator: false, enabled: b.hasSelection),
                MenuItemSpec(label: "~C~opy", shortcut: "", cmd: .copy, separator: false, enabled: b.hasSelection),
                MenuItemSpec(label: "~P~aste", shortcut: "", cmd: .paste, separator: false),
                MenuItemSpec(label: "", shortcut: "", cmd: nil, separator: true),
                MenuItemSpec(label: "Select ~A~ll", shortcut: "", cmd: .selectAll, separator: false),
                MenuItemSpec(label: "~F~ind...", shortcut: "", cmd: .find, separator: false),
                MenuItemSpec(label: "", shortcut: "", cmd: nil, separator: true),
                MenuItemSpec(label: "~S~ave", shortcut: "", cmd: .save, separator: false),
                MenuItemSpec(label: "~C~lose", shortcut: "", cmd: .closeWindow, separator: false),
            ]
            var width = 20
            for item in items {
                width = max(width, AppState.displayWidth(item.label) + 6)
            }
            let height = items.count + 2
            let rect = CellRect(x: min(max(0, x), 80 - width),
                                y: min(max(AppState.desktopTop, y), 24 - height),
                                w: width, h: height)
            let first = items.firstIndex { !$0.separator } ?? 0
            contextMenu = ContextMenu(items: items, rect: rect, cursor: first)
            return
        }
    }

    private func handleContextClick(x: Int, y: Int) {
        guard let cm = contextMenu else { return }
        if cm.rect.contains(x, y) {
            let item = y - cm.rect.y - 1
            if item >= 0 && item < cm.items.count {
                let entry = cm.items[item]
                if !entry.separator, let cmd = entry.cmd, entry.enabled {
                    contextMenu = nil
                    perform(cmd)
                    return
                }
            }
            return
        }
        contextMenu = nil
    }

    func cursorKind(x: Int, y: Int) -> CursorKind {
        if let d = dialog {
            if d.inputs.contains(where: { $0.rect.contains(x, y) }) { return .ibeam }
            if d.buttons.contains(where: { $0.rect.contains(x, y) }) { return .hand }
            return .arrow
        }
        if contextMenu != nil || menuOpen != nil { return .hand }
        if y == AppState.menuRow { return .hand }
        if y == AppState.toolbarRow {
            return toolButton(atX: x) != nil ? .hand : .arrow
        }
        if y == AppState.statusRow {
            return statusSegment(atX: x) != nil ? .hand : .arrow
        }
        for w in windows.reversed() where w.rect.contains(x, y) {
            let f = w.rect
            if y == f.y { return .hand }
            if x == f.maxX && y == f.maxY { return .resize }
            let ta = AppState.textArea(f)
            if ta.contains(x, y) { return .ibeam }
            return .hand
        }
        return .arrow
    }

    // MARK: - Drawing

    func render(into s: Screen) {
        s.clear(" ", fg: EGA.gray, bg: EGA.blue)
        for y in AppState.desktopTop..<24 {
            for x in 0..<80 {
                s.set(x, y, "░", fg: EGA.gray, bg: EGA.blue)
            }
        }
        drawMenuBar(into: s)
        drawToolbar(into: s)
        for (i, w) in windows.enumerated() {
            drawWindow(w, active: i == windows.count - 1, into: s)
        }
        drawStatus(into: s)
        if let open = menuOpen { drawMenu(open, into: s) }
        drawContextMenu(into: s)
        if let d = dialog { d.draw(on: s, cursorOn: cursorOn) }
    }

    private func drawMenuBar(into s: Screen) {
        for x in 0..<80 { s.set(x, 0, " ", fg: EGA.black, bg: EGA.gray) }
        let placements = menuBarPlacements()
        for (i, title) in AppState.menuTitles.enumerated() {
            let p = placements[i]
            let hovered = hoverCell.map {
                $0.y == AppState.menuRow && menuIndex(atX: $0.x) == i
            } ?? false
            let selected = menuOpen == i
            let bg = (selected || hovered) ? EGA.green : EGA.gray
            let fg = EGA.black
            s.put(p.x, 0, " " + title + " ", fg: fg, bg: bg)
            s.set(p.x + 1, 0, title.first ?? " ", fg: selected ? EGA.black : EGA.red, bg: bg)
        }
        let clockX = 80 - clockText.count - 1
        s.put(clockX, 0, clockText, fg: EGA.black, bg: EGA.gray)
    }

    private func drawToolbar(into s: Screen) {
        for x in 0..<80 {
            s.set(x, AppState.toolbarRow, " ", fg: EGA.black, bg: EGA.gray)
        }
        for button in toolButtons() {
            let enabled = isEnabled(button.cmd)
            let hovered = hoverCell.map { button.rect.contains($0.x, $0.y) } ?? false
            let bg = (hovered && enabled) ? EGA.green : EGA.gray
            let fg = enabled ? EGA.black : EGA.darkGray
            s.fill(button.rect, " ", fg: fg, bg: bg)
            s.put(button.rect.x, AppState.toolbarRow, "[ \(button.title) ]", fg: fg, bg: bg)
        }
    }

    private func drawStatus(into s: Screen) {
        for x in 0..<80 { s.set(x, AppState.statusRow, " ", fg: EGA.black, bg: EGA.gray) }
        for seg in statusSegments() {
            let enabled = isEnabled(seg.cmd)
            let hovered = hoverCell.map {
                $0.y == AppState.statusRow && $0.x >= seg.x && $0.x < seg.x + seg.w
            } ?? false
            let bg = (hovered && enabled) ? EGA.green : EGA.gray
            let fg = enabled ? EGA.black : EGA.darkGray
            s.fill(CellRect(x: seg.x, y: AppState.statusRow, w: seg.w, h: 1), " ", fg: fg, bg: bg)
            s.put(seg.x, AppState.statusRow, seg.hot, fg: enabled ? EGA.red : EGA.darkGray, bg: bg)
            s.put(seg.x + seg.hot.count, AppState.statusRow, seg.rest, fg: fg, bg: bg)
        }
        if let msg = statusText {
            let trimmed = String(msg.prefix(20))
            let x = max(62, 79 - trimmed.count)
            s.put(x, AppState.statusRow, trimmed, fg: EGA.black, bg: EGA.gray)
        }
    }

    private func drawContextMenu(into s: Screen) {
        guard let cm = contextMenu else { return }
        s.shadow(cm.rect)
        s.thinBox(cm.rect, fg: EGA.black, bg: EGA.gray)
        for (i, item) in cm.items.enumerated() {
            let y = cm.rect.y + 1 + i
            if item.separator {
                s.set(cm.rect.x, y, "├", fg: EGA.black, bg: EGA.gray)
                s.set(cm.rect.maxX, y, "┤", fg: EGA.black, bg: EGA.gray)
                for x in (cm.rect.x + 1)..<cm.rect.maxX {
                    s.set(x, y, "─", fg: EGA.black, bg: EGA.gray)
                }
                continue
            }
            let selected = i == cm.cursor
            let bg = selected ? EGA.green : EGA.gray
            let fg = item.enabled ? EGA.black : EGA.darkGray
            for x in (cm.rect.x + 1)..<cm.rect.maxX {
                s.set(x, y, " ", fg: fg, bg: bg)
            }
            s.putHot(cm.rect.x + 2, y, item.label, fg: fg,
                     hot: selected ? EGA.black : EGA.red, bg: bg,
                     limit: cm.rect.w - 3)
        }
    }

    private func drawWindow(_ w: EditorWindow, active: Bool, into s: Screen) {
        let f = w.rect
        s.shadow(f)
        s.box(f, fg: active ? EGA.white : EGA.gray, bg: EGA.blue)

        let ta = AppState.textArea(f)
        w.buffer.viewWidth = ta.w
        w.buffer.viewHeight = ta.h

        let title = w.buffer.modified ? w.buffer.title + " *" : w.buffer.title
        let inner = f.w - 2
        let maxTitle = max(0, inner - 14)
        let shown = title.count > maxTitle ? String(title.prefix(maxTitle)) : title
        let tx = f.x + 1 + (inner - shown.count - 2) / 2
        if shown.count > 0 && shown.count + 2 <= inner - 10 {
            s.put(tx - 1, f.y, " ", fg: EGA.white, bg: EGA.blue)
            s.put(tx, f.y, shown, fg: active ? EGA.white : EGA.gray, bg: EGA.blue)
            s.put(tx + shown.count, f.y, " ", fg: EGA.white, bg: EGA.blue)
        }

        let closeHovered = hoverCell.map { $0.y == f.y && $0.x >= f.x + 2 && $0.x <= f.x + 4 } ?? false
        let zoomHovered = hoverCell.map { $0.y == f.y && $0.x >= f.maxX - 4 && $0.x <= f.maxX - 2 } ?? false
        let closeBG = closeHovered ? EGA.green : EGA.blue
        let zoomBG = zoomHovered ? EGA.green : EGA.blue
        s.put(f.x + 2, f.y, "[", fg: closeHovered ? EGA.black : EGA.white, bg: closeBG)
        s.put(f.x + 3, f.y, "■", fg: closeHovered ? EGA.black : EGA.green, bg: closeBG)
        s.put(f.x + 4, f.y, "]", fg: closeHovered ? EGA.black : EGA.white, bg: closeBG)
        s.put(f.maxX - 4, f.y, "[", fg: zoomHovered ? EGA.black : EGA.white, bg: zoomBG)
        s.put(f.maxX - 3, f.y, w.zoomed ? "↕" : "↑", fg: zoomHovered ? EGA.black : EGA.green, bg: zoomBG)
        s.put(f.maxX - 2, f.y, "]", fg: zoomHovered ? EGA.black : EGA.white, bg: zoomBG)

        let b = w.buffer
        for row in 0..<ta.h {
            let li = b.scrollLine + row
            for cx in 0..<ta.w {
                let ci = b.scrollCol + cx
                var ch: Character = " "
                if li < b.lines.count && ci < b.lines[li].count {
                    ch = b.lines[li][ci]
                }
                var fg = EGA.white
                var bg = EGA.blue
                if let (selStart, selEnd) = b.selection {
                    let afterStart = li > selStart.0 || (li == selStart.0 && ci >= selStart.1)
                    let beforeEnd = li < selEnd.0 || (li == selEnd.0 && ci < selEnd.1)
                    if afterStart && beforeEnd {
                        fg = EGA.blue
                        bg = EGA.gray
                    }
                }
                if active && cursorOn && li == b.line && ci == b.col {
                    fg = EGA.blue
                    bg = EGA.white
                }
                s.set(ta.x + cx, ta.y + row, ch, fg: fg, bg: bg)
            }
        }

        // vertical scroll bar
        let sx = f.maxX - 1
        let vg = verticalScroll(w)
        s.set(sx, f.y + 1, "▲", fg: EGA.white, bg: EGA.blue)
        s.set(sx, f.maxY - 1, "▼", fg: EGA.white, bg: EGA.blue)
        for y in vg.trackStart..<(vg.trackStart + vg.trackLen) {
            s.set(sx, y, "▒", fg: EGA.cyan, bg: EGA.blue)
        }
        for y in vg.thumbStart..<(vg.thumbStart + vg.thumbLen) {
            s.set(sx, y, "█", fg: EGA.white, bg: EGA.blue)
        }

        // indicator and horizontal scroll bar on the bottom border
        s.put(f.x + 2, f.maxY, b.modified ? "☼" : " ", fg: EGA.white, bg: EGA.blue)
        let pos = "\(b.line + 1):\(b.col + 1)"
        s.put(f.x + 4, f.maxY, pos, fg: EGA.white, bg: EGA.blue)

        let hs = f.x + 14
        let he = f.maxX - 1
        if he - hs > 4 {
            let hg = horizontalScroll(w)
            s.set(hs, f.maxY, "◄", fg: EGA.white, bg: EGA.blue)
            s.set(he, f.maxY, "►", fg: EGA.white, bg: EGA.blue)
            for x in hg.trackStart..<(hg.trackStart + hg.trackLen) {
                s.set(x, f.maxY, "▒", fg: EGA.cyan, bg: EGA.blue)
            }
            for x in hg.thumbStart..<(hg.thumbStart + hg.thumbLen) {
                s.set(x, f.maxY, "█", fg: EGA.white, bg: EGA.blue)
            }
        }

        // resize grip in the bottom-right corner
        s.set(f.maxX, f.maxY, "▄", fg: active ? EGA.gray : EGA.darkGray, bg: EGA.blue)
    }

    private func drawMenu(_ index: Int, into s: Screen) {
        let geo = menuGeometry(index)
        let specs = menuSpecs()[index]
        s.shadow(geo)
        s.thinBox(geo, fg: EGA.black, bg: EGA.gray)
        for (i, item) in specs.enumerated() {
            let y = geo.y + 1 + i
            if item.separator {
                s.set(geo.x, y, "├", fg: EGA.black, bg: EGA.gray)
                s.set(geo.maxX, y, "┤", fg: EGA.black, bg: EGA.gray)
                for x in (geo.x + 1)..<geo.maxX {
                    s.set(x, y, "─", fg: EGA.black, bg: EGA.gray)
                }
                continue
            }
            let selected = i == menuCursor
            let bg = selected ? EGA.green : EGA.gray
            let fg = item.enabled ? (selected ? EGA.black : EGA.black) : EGA.darkGray
            for x in (geo.x + 1)..<geo.maxX {
                s.set(x, y, " ", fg: fg, bg: bg)
            }
            s.putHot(geo.x + 2, y, item.label, fg: fg, hot: selected ? EGA.black : EGA.red,
                     bg: bg, limit: geo.w - 3)
            if !item.shortcut.isEmpty {
                let sx = geo.maxX - 1 - item.shortcut.count
                s.put(sx, y, item.shortcut, fg: fg, bg: bg)
            }
        }
    }
}
