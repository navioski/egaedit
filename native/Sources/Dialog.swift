import Foundation

enum DialogKind {
    case about
    case keys
    case find
    case replace
    case savePrompt(Int)
    case message
}

enum DialogAction {
    case ok
    case cancel
    case yes
    case no
    case find
    case replaceAll
}

struct DInput {
    var rect: CellRect
    var text: String = ""
    var cursor: Int = 0
}

struct DButton {
    var rect: CellRect
    var label: String
    var action: DialogAction
    var isDefault: Bool = false
}

/// A modal dialog drawn in the same character grid as everything else.
final class Dialog {
    let kind: DialogKind
    let title: String
    let frame: CellRect
    var texts: [(Int, Int, String)] = []
    var banner: (x: Int, y: Int, w: Int, text: String)?
    var palette: (x: Int, y: Int)?
    var inputs: [DInput] = []
    var buttons: [DButton] = []
    var focus = 0

    init(kind: DialogKind, title: String, frame: CellRect) {
        self.kind = kind
        self.title = title
        self.frame = frame
    }

    var controlCount: Int { inputs.count + buttons.count }

    private func rectForButtons(_ labels: [(String, DialogAction, Bool)], y: Int) -> [DButton] {
        var widths: [Int] = []
        for (label, _, isDefault) in labels {
            widths.append(label.count + (isDefault ? 6 : 4))
        }
        let gap = 2
        let total = widths.reduce(0, +) + gap * (labels.count - 1)
        var x = frame.x + (frame.w - total) / 2
        var result: [DButton] = []
        for (i, item) in labels.enumerated() {
            let w = widths[i]
            result.append(DButton(rect: CellRect(x: x, y: y, w: w, h: 1),
                                  label: item.0, action: item.1, isDefault: item.2))
            x += w + gap
        }
        return result
    }

    // MARK: - Builders

    static func about() -> Dialog {
        let f = CellRect(x: 11, y: 5, w: 58, h: 15)
        let d = Dialog(kind: .about, title: "About", frame: f)
        d.banner = (f.x + 1, f.y + 1, f.w - 2, "E G A   E D I T   1.0")
        d.texts = [
            (f.x + 3, f.y + 3, "A Turbo Vision style text editor."),
            (f.x + 3, f.y + 5, "Every pixel is a character cell."),
            (f.x + 3, f.y + 6, "EGA colours, double-line frames, no anti-aliasing."),
            (f.x + 23, f.y + 8, "EGA 16-colour palette"),
            (f.x + 3, f.y + 10, "Built with AppKit and Core Graphics."),
            (f.x + 3, f.y + 11, "Font: PxPlus IBM VGA8, 8x16 pixels. F1 for keys."),
        ]
        d.palette = (f.x + 3, f.y + 8)
        d.buttons = d.rectForButtons([("OK", .ok, true)], y: f.maxY - 2)
        d.focus = d.inputs.count
        return d
    }

    static func keys() -> Dialog {
        let f = CellRect(x: 5, y: 2, w: 70, h: 21)
        let d = Dialog(kind: .keys, title: "Keyboard", frame: f)
        let lines = [
            "F1  Keyboard   F2  Save     F3  Open    F4  New",
            "F5  Zoom       F6  Next     F10 Menu    Cmd-Q  Quit",
            "",
            "Cmd-N  New            Cmd-O  Open        Cmd-S  Save",
            "Cmd-Z  Undo           Cmd-X  Cut         Cmd-C  Copy",
            "Cmd-V  Paste          Cmd-A  Select all  Cmd-W  Close",
            "Cmd-F  Find           Cmd-R  Replace     Cmd-G  Again",
            "",
            "Tab / Shift-Tab  Move focus       Enter  Default button",
            "Esc  Cancel dialog or close menu  Option+letter  Menu",
            "",
            "Mouse: click a title to move a window, click text to set the caret.",
        ]
        for (i, line) in lines.enumerated() {
            d.texts.append((f.x + 3, f.y + 2 + i, line))
        }
        d.buttons = d.rectForButtons([("OK", .ok, true)], y: f.maxY - 2)
        return d
    }

    static func find() -> Dialog {
        let f = CellRect(x: 17, y: 8, w: 46, h: 9)
        let d = Dialog(kind: .find, title: "Find", frame: f)
        d.texts = [(f.x + 3, f.y + 2, "Text to find")]
        d.inputs = [DInput(rect: CellRect(x: f.x + 3, y: f.y + 3, w: f.w - 6, h: 1))]
        d.buttons = d.rectForButtons([("Find", .find, true), ("Cancel", .cancel, false)],
                                     y: f.y + 6)
        d.focus = 0
        return d
    }

    static func replace() -> Dialog {
        let f = CellRect(x: 15, y: 6, w: 50, h: 12)
        let d = Dialog(kind: .replace, title: "Replace", frame: f)
        d.texts = [
            (f.x + 3, f.y + 2, "Text to find"),
            (f.x + 3, f.y + 5, "Replace with"),
        ]
        d.inputs = [
            DInput(rect: CellRect(x: f.x + 3, y: f.y + 3, w: f.w - 6, h: 1)),
            DInput(rect: CellRect(x: f.x + 3, y: f.y + 6, w: f.w - 6, h: 1)),
        ]
        d.buttons = d.rectForButtons([("Replace All", .replaceAll, true),
                                      ("Cancel", .cancel, false)],
                                     y: f.y + 9)
        d.focus = 0
        return d
    }

    static func savePrompt(name: String, index: Int) -> Dialog {
        let f = CellRect(x: 15, y: 9, w: 50, h: 8)
        let d = Dialog(kind: .savePrompt(index), title: "Save", frame: f)
        d.texts = [
            (f.x + 3, f.y + 2, "\(name) has been modified."),
            (f.x + 3, f.y + 3, "Save before closing?"),
        ]
        d.buttons = d.rectForButtons([("Yes", .yes, true), ("No", .no, false),
                                      ("Cancel", .cancel, false)],
                                     y: f.y + 5)
        return d
    }

    static func message(_ text: String) -> Dialog {
        let w = max(40, min(74, text.count + 8))
        let f = CellRect(x: (80 - w) / 2, y: 10, w: w, h: 7)
        let d = Dialog(kind: .message, title: "Information", frame: f)
        d.texts = [(f.x + 3, f.y + 2, text)]
        d.buttons = d.rectForButtons([("OK", .ok, true)], y: f.y + 4)
        return d
    }

    // MARK: - Drawing

    func draw(on s: Screen, cursorOn: Bool) {
        s.shadow(frame)
        s.box(frame, fg: EGA.white, bg: EGA.gray)

        // title
        let titleText = " " + title + " "
        let tx = frame.x + (frame.w - titleText.count) / 2
        s.put(tx, frame.y, titleText, fg: EGA.white, bg: EGA.gray)
        // close icon
        s.put(frame.x + 2, frame.y, "[", fg: EGA.white, bg: EGA.gray)
        s.put(frame.x + 3, frame.y, "■", fg: EGA.green, bg: EGA.gray)
        s.put(frame.x + 4, frame.y, "]", fg: EGA.white, bg: EGA.gray)

        if let b = banner {
            for x in b.x..<(b.x + b.w) {
                s.set(x, b.y, " ", fg: EGA.black, bg: EGA.cyan)
            }
            let tx = b.x + (b.w - b.text.count) / 2
            s.put(tx, b.y, b.text, fg: EGA.black, bg: EGA.cyan)
        }

        for (x, y, text) in texts {
            s.put(x, y, text, fg: EGA.black, bg: EGA.gray)
        }

        if let p = palette {
            let colors: [RGB] = [
                EGA.black, EGA.blue, EGA.green, EGA.cyan, EGA.red, EGA.magenta, EGA.brown, EGA.gray,
                EGA.darkGray, EGA.lightBlue, EGA.lightGreen, EGA.lightCyan, EGA.lightRed,
                EGA.lightMagenta, EGA.yellow, EGA.white,
            ]
            for (i, c) in colors.enumerated() {
                s.set(p.x + i, p.y, "█", fg: c, bg: c)
            }
        }

        for (i, input) in inputs.enumerated() {
            let focused = focus == i
            s.fill(input.rect, " ", fg: EGA.white, bg: EGA.blue)
            s.put(input.rect.x, input.rect.y, input.text, fg: EGA.white, bg: EGA.blue)
            if focused {
                let cx = input.rect.x + min(input.cursor, input.rect.w - 1)
                let ch: Character = input.cursor < input.text.count
                    ? Array(input.text)[input.cursor] : " "
                s.set(cx, input.rect.y, ch, fg: EGA.blue, bg: EGA.white)
            }
        }

        for (i, button) in buttons.enumerated() {
            let selected = focus == inputs.count + i
            let bg = selected ? EGA.green : EGA.gray
            let fg = selected ? EGA.black : EGA.black
            s.fill(button.rect, " ", fg: fg, bg: bg)
            let label = button.isDefault ? "◄ \(button.label) ►" : "[ \(button.label) ]"
            let x = button.rect.x + max(0, (button.rect.w - label.count) / 2)
            s.put(x, button.rect.y, label, fg: fg, bg: bg)
        }
    }

    // MARK: - Input

    func key(_ key: KeyEvent) -> DialogAction? {
        if key.keyCode == 53 { return .cancel } // esc
        if key.keyCode == 48 { // tab
            if controlCount > 0 {
                focus = (focus + (key.shift ? controlCount - 1 : 1)) % controlCount
            }
            return nil
        }
        if key.keyCode == 36 || key.keyCode == 76 { // return / keypad enter
            if focus >= inputs.count {
                return buttons[focus - inputs.count].action
            }
            if let def = buttons.first(where: { $0.isDefault }) { return def.action }
            return buttons.first?.action ?? .cancel
        }
        if key.keyCode == 125 || key.keyCode == 126 { // up / down
            if controlCount > 0 {
                focus = (focus + (key.keyCode == 125 ? 1 : controlCount - 1)) % controlCount
            }
            return nil
        }

        guard focus < inputs.count else {
            if key.chars == " " && focus >= inputs.count {
                return buttons[focus - inputs.count].action
            }
            return nil
        }

        let idx = focus
        var input = inputs[idx]
        var chars = Array(input.text)
        switch key.keyCode {
        case 51: // backspace
            if input.cursor > 0 && input.cursor <= chars.count {
                chars.remove(at: input.cursor - 1)
                input.cursor -= 1
            }
        case 117: // forward delete
            if input.cursor < chars.count { chars.remove(at: input.cursor) }
        case 123:
            if input.cursor > 0 { input.cursor -= 1 }
        case 124:
            if input.cursor < chars.count { input.cursor += 1 }
        case 115:
            input.cursor = 0
        case 119:
            input.cursor = chars.count
        default:
            for ch in key.chars where !ch.isNewline {
                if ch.asciiValue == nil && ch.unicodeScalars.first!.value < 32 { continue }
                if input.cursor <= chars.count {
                    chars.insert(ch, at: input.cursor)
                    input.cursor += 1
                }
            }
        }
        input.text = String(chars)
        input.cursor = min(input.cursor, chars.count)
        inputs[idx] = input
        return nil
    }

    func insertText(_ text: String) {
        guard focus < inputs.count else { return }
        var input = inputs[focus]
        var chars = Array(input.text)
        for ch in text where !ch.isNewline {
            if input.cursor <= chars.count {
                chars.insert(ch, at: input.cursor)
                input.cursor += 1
            }
        }
        input.text = String(chars)
        inputs[focus] = input
    }

    func click(_ x: Int, _ y: Int) -> DialogAction? {
        for (i, input) in inputs.enumerated() where input.rect.contains(x, y) {
            focus = i
            let offset = x - input.rect.x
            inputs[i].cursor = min(max(0, offset), inputs[i].text.count)
            return nil
        }
        for (i, button) in buttons.enumerated() where button.rect.contains(x, y) {
            focus = inputs.count + i
            return button.action
        }
        return nil
    }
}
