import Foundation

enum SelfTest {
    static func check(_ cond: Bool, _ label: String) {
        if !cond {
            print("FAIL: \(label)")
            exit(1)
        }
    }

    static func run() {
        let b = TextBuffer(text: "abc\ndef", url: nil)
        b.insert("X")
        check(b.text() == "Xabc\ndef", "insert at start")
        check(b.col == 1, "column after insert")
        b.undo()
        check(b.text() == "abc\ndef", "undo insert")

        b.setCursor(line: 0, col: 3, selecting: false)
        b.newline()
        check(b.text() == "abc\n\ndef", "newline splits line")
        b.backspace()
        check(b.text() == "abc\ndef", "backspace joins lines")

        b.setCursor(line: 1, col: 2, selecting: false)
        b.backspace()
        check(b.text() == "abc\ndf", "backspace mid line")

        b.setCursor(line: 0, col: 0, selecting: false)
        b.moveRight(selecting: true)
        b.moveRight(selecting: true)
        check(b.selectedText() == "ab", "selection text")
        b.insert("ZZ")
        check(b.text() == "ZZc\ndf", "replace selection")
        b.undo()
        check(b.text() == "abc\ndf", "undo replace")

        let c = TextBuffer(text: "one two one\ntwo three", url: nil)
        check(c.find("one"), "find first")
        check(c.find("one"), "find next")
        let replaced = c.replaceAll("one", with: "1")
        check(replaced == 2, "replace count")
        check(c.text() == "1 two 1\ntwo three", "replace text")

        let d = TextBuffer(text: "line one\nline two\n", url: nil)
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ega-selftest.txt")
        check(d.save(to: url), "save to temp")
        let loaded = try? String(contentsOf: url, encoding: .utf8)
        check(loaded == "line one\nline two\n", "saved contents")

        let state = AppState()
        state.newWindow(text: "hello world")
        StateCheck(state: state)
        state.perform(.selectAll)
        check(state.activeWindow?.buffer.selectedText() == "hello world", "select all")
        state.perform(.find)
        check(state.dialog != nil, "find dialog open")
        state.dialog?.inputs[0].text = "world"
        state.handleDialogAction(.find)
        check(state.activeWindow?.buffer.selectedText() == "world", "find via dialog")
        state.perform(.replace)
        state.dialog?.inputs[0].text = "world"
        state.dialog?.inputs[1].text = "there"
        state.handleDialogAction(.replaceAll)
        check(state.activeWindow?.buffer.text() == "hello there", "replace all via dialog")

        // Mouse-first interactions
        let mouse = AppState()
        mouse.newWindow(text: "hello world")
        let before = mouse.windows.count
        mouse.mouseDown(x: 3, y: AppState.toolbarRow, shift: false, clicks: 1)
        check(mouse.windows.count == before + 1, "toolbar New creates a window")
        mouse.removeWindow(mouse.windows.count - 1)

        let frame = mouse.activeWindow!.rect
        let ta = AppState.textArea(frame)
        mouse.mouseDown(x: ta.x, y: ta.y, shift: false, clicks: 1)
        mouse.mouseDragged(x: ta.x + 3, y: ta.y)
        mouse.mouseUp()
        check(mouse.activeWindow?.buffer.hasSelection == true, "mouse drag selects")

        mouse.mouseDown(x: ta.x + 2, y: ta.y, shift: false, clicks: 2)
        check(mouse.activeWindow?.buffer.hasSelection == true, "double click selects word")
        mouse.mouseUp()

        mouse.rightClick(x: ta.x + 2, y: ta.y + 1)
        check(mouse.isContextMenuOpen, "right click opens context menu")
        mouse.mouseDown(x: 2, y: 2, shift: false, clicks: 1) // outside closes
        check(!mouse.isContextMenuOpen, "click outside closes context menu")

        let oldWidth = mouse.activeWindow!.rect.w
        let f2 = mouse.activeWindow!.rect
        mouse.mouseDown(x: f2.maxX, y: f2.maxY, shift: false, clicks: 1)
        mouse.mouseDragged(x: f2.maxX - 6, y: f2.maxY - 2)
        mouse.mouseUp()
        check(mouse.activeWindow!.rect.w < oldWidth, "corner drag resizes the window")

        mouse.scrollWheel(x: ta.x + 1, y: ta.y + 1, dy: -1, dx: 0,
                          precise: false, pointsPerLine: 24)
        check(mouse.activeWindow!.buffer.scrollLine >= 0, "wheel scroll stays sane")

        let longText = (0..<200).map { "line \($0)" }.joined(separator: "\n")
        let scrollState = AppState()
        scrollState.newWindow(text: longText)
        let stFrame = scrollState.activeWindow!.rect
        let stTA = AppState.textArea(stFrame)
        scrollState.scrollWheel(x: stTA.x + 2, y: stTA.y + 2, dy: -48, dx: 0,
                                precise: true, pointsPerLine: 24)
        check(scrollState.activeWindow!.buffer.scrollLine == 2, "precise trackpad scroll moves two lines")
        let beforeRender = scrollState.activeWindow!.buffer.scrollLine
        let scratch = Screen(cols: 80, rows: 25)
        scrollState.render(into: scratch)
        check(scrollState.activeWindow!.buffer.scrollLine == beforeRender,
              "rendering does not snap the scroll back")
        for _ in 0..<300 {
            scrollState.scrollWheel(x: stTA.x + 2, y: stTA.y + 2, dy: -20, dx: 0,
                                    precise: true, pointsPerLine: 24)
        }
        check(scrollState.activeWindow!.buffer.scrollLine <= 200 - stTA.h,
              "trackpad scrolling clamps at the end")

        // Render every screen we ship to make sure drawing is crash free.
        let screens: [String] = ["main", "menu", "about", "keys", "find", "replace"]
        for name in screens {
            let st = AppState()
            st.newWindow(text: "hello")
            switch name {
            case "menu": st.openMenu(0); st.menuCursor = 1
            case "about": st.dialog = Dialog.about()
            case "keys": st.dialog = Dialog.keys()
            case "find": st.dialog = Dialog.find()
            case "replace": st.dialog = Dialog.replace()
            default: break
            }
            let screen = Screen(cols: 80, rows: 25)
            st.render(into: screen)
            let glyphs = try! GlyphSet(binURL: URL(fileURLWithPath: "Resources/glyphs.bin"),
                                       jsonURL: URL(fileURLWithPath: "Resources/glyphs.json"))
            let image = Renderer(glyphs: glyphs, cols: 80, rows: 25).makeImage(screen)
            check(image != nil, "render \(name)")
        }
        print("selftest ok")
    }

    private static func StateCheck(state: AppState) {
        check(!state.windows.isEmpty, "window created")
    }
}
