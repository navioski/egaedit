import Foundation

struct EditSnapshot {
    var lines: [[Character]]
    var line: Int
    var col: Int
    var anchor: (Int, Int)?
    var modified: Bool
}

/// Line-based text buffer with a caret, selection, undo and a viewport.
final class TextBuffer {
    var lines: [[Character]] = [[]]
    var line = 0
    var col = 0
    var anchor: (Int, Int)?
    var modified = false
    var overwrite = false
    var fileURL: URL?
    var displayTitle: String?

    // Set by the window before drawing.
    var viewWidth = 73
    var viewHeight = 20
    var scrollLine = 0
    var scrollCol = 0

    private var undoStack: [EditSnapshot] = []
    private let undoLimit = 200

    init() {}

    convenience init(text: String, url: URL?) {
        self.init()
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var parsed = normalized.split(separator: "\n", omittingEmptySubsequences: false)
            .map { Array($0) }
        if parsed.isEmpty { parsed = [[]] }
        lines = parsed
        fileURL = url
    }

    var title: String {
        if let t = displayTitle { return t }
        if let url = fileURL { return url.lastPathComponent }
        return "Untitled"
    }

    var displayName: String { title }

    var lineCount: Int { lines.count }

    func lineLength(_ index: Int) -> Int {
        guard index >= 0 && index < lines.count else { return 0 }
        return lines[index].count
    }

    var selection: ((Int, Int), (Int, Int))? {
        guard let a = anchor else { return nil }
        let p = (line, col)
        if a.0 == p.0 && a.1 == p.1 { return nil }
        if a.0 < p.0 || (a.0 == p.0 && a.1 < p.1) { return (a, p) }
        return (p, a)
    }

    var hasSelection: Bool { selection != nil }

    func selectedText() -> String {
        guard let (s, e) = selection else { return "" }
        if s.0 == e.0 {
            let chars = lines[s.0]
            let a = min(max(s.1, 0), chars.count)
            let b = min(max(e.1, 0), chars.count)
            if a >= b { return "" }
            return String(chars[a..<b])
        }
        var out = String(lines[s.0][min(s.1, lines[s.0].count)...])
        if s.0 + 1 < e.0 {
            for i in (s.0 + 1)..<e.0 {
                out += "\n" + String(lines[i])
            }
        }
        out += "\n" + String(lines[e.0][..<min(e.1, lines[e.0].count)])
        return out
    }

    // MARK: - Undo

    private func snapshot() -> EditSnapshot {
        EditSnapshot(lines: lines, line: line, col: col, anchor: anchor, modified: modified)
    }

    private func pushUndo() {
        undoStack.append(snapshot())
        if undoStack.count > undoLimit {
            undoStack.removeFirst(undoStack.count - undoLimit)
        }
    }

    var canUndo: Bool { !undoStack.isEmpty }

    func undo() {
        guard let snap = undoStack.popLast() else { return }
        lines = snap.lines
        line = min(snap.line, max(0, lines.count - 1))
        col = min(snap.col, lineLength(line))
        anchor = snap.anchor
        modified = snap.modified
        ensureVisible()
    }

    // MARK: - Editing

    func insert(_ text: String) {
        guard !text.isEmpty else { return }
        pushUndo()
        if hasSelection { deleteSelectionInternal() }

        let parts = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        insertRaw(parts[0])
        for i in 1..<parts.count {
            let cut = min(col, lines[line].count)
            let tail = Array(lines[line][cut...])
            lines[line].removeSubrange(cut..<lines[line].count)
            lines.insert(tail, at: line + 1)
            line += 1
            col = 0
            insertRaw(parts[i])
        }
        modified = true
        anchor = nil
        ensureVisible()
    }

    private func insertRaw(_ s: String) {
        let chars = Array(s)
        guard !chars.isEmpty else { return }
        if overwrite {
            for ch in chars {
                if col < lines[line].count {
                    lines[line][col] = ch
                } else {
                    lines[line].append(ch)
                }
                col += 1
            }
            return
        }
        lines[line].insert(contentsOf: chars, at: min(col, lines[line].count))
        col += chars.count
    }

    func newline() {
        insert("\n")
    }

    func backspace() {
        if hasSelection {
            pushUndo()
            deleteSelectionInternal()
            modified = true
            return
        }
        pushUndo()
        if col > 0 {
            lines[line].remove(at: col - 1)
            col -= 1
        } else if line > 0 {
            let prevLen = lines[line - 1].count
            lines[line - 1].append(contentsOf: lines[line])
            lines.remove(at: line)
            line -= 1
            col = prevLen
        } else {
            undoStack.removeLast()
            return
        }
        modified = true
        ensureVisible()
    }

    func deleteForward() {
        if hasSelection {
            pushUndo()
            deleteSelectionInternal()
            modified = true
            return
        }
        pushUndo()
        if col < lineLength(line) {
            lines[line].remove(at: col)
        } else if line + 1 < lines.count {
            lines[line].append(contentsOf: lines[line + 1])
            lines.remove(at: line + 1)
        } else {
            undoStack.removeLast()
            return
        }
        modified = true
        ensureVisible()
    }

    func deleteSelection() {
        guard hasSelection else { return }
        pushUndo()
        deleteSelectionInternal()
        modified = true
    }

    private func deleteSelectionInternal() {
        guard let (s, e) = selection else { return }
        if s.0 == e.0 {
            lines[s.0].removeSubrange(s.1..<e.1)
            line = s.0
            col = s.1
        } else {
            let head = Array(lines[s.0][..<min(s.1, lines[s.0].count)])
            let tail = Array(lines[e.0][min(e.1, lines[e.0].count)...])
            lines[s.0] = head + tail
            lines.removeSubrange((s.0 + 1)...e.0)
            line = s.0
            col = s.1
        }
        anchor = nil
    }

    // MARK: - Movement

    func setCursor(line newLine: Int, col newCol: Int, selecting: Bool) {
        if selecting {
            if anchor == nil { anchor = (line, col) }
        } else {
            anchor = nil
        }
        line = min(max(newLine, 0), max(0, lines.count - 1))
        col = min(max(newCol, 0), lineLength(line))
        ensureVisible()
    }

    func moveLeft(selecting: Bool) {
        let keep = selecting ? (anchor ?? (line, col)) : nil
        if col > 0 { col -= 1 }
        else if line > 0 { line -= 1; col = lineLength(line) }
        anchor = keep
        ensureVisible()
    }

    func moveRight(selecting: Bool) {
        let keep = selecting ? (anchor ?? (line, col)) : nil
        if col < lineLength(line) { col += 1 }
        else if line + 1 < lines.count { line += 1; col = 0 }
        anchor = keep
        ensureVisible()
    }

    func moveUp(selecting: Bool) {
        let keep = selecting ? (anchor ?? (line, col)) : nil
        if line > 0 { line -= 1; col = min(col, lineLength(line)) }
        anchor = keep
        ensureVisible()
    }

    func moveDown(selecting: Bool) {
        let keep = selecting ? (anchor ?? (line, col)) : nil
        if line + 1 < lines.count { line += 1; col = min(col, lineLength(line)) }
        anchor = keep
        ensureVisible()
    }

    func home(selecting: Bool) {
        let keep = selecting ? (anchor ?? (line, col)) : nil
        col = 0
        anchor = keep
        ensureVisible()
    }

    func end(selecting: Bool) {
        let keep = selecting ? (anchor ?? (line, col)) : nil
        col = lineLength(line)
        anchor = keep
        ensureVisible()
    }

    func pageUp(selecting: Bool) {
        let keep = selecting ? (anchor ?? (line, col)) : nil
        line = max(0, line - viewHeight)
        col = min(col, lineLength(line))
        anchor = keep
        ensureVisible()
    }

    func pageDown(selecting: Bool) {
        let keep = selecting ? (anchor ?? (line, col)) : nil
        line = min(lines.count - 1, line + viewHeight)
        col = min(col, lineLength(line))
        anchor = keep
        ensureVisible()
    }

    func selectWord(line l: Int, col c: Int) {
        guard l >= 0 && l < lines.count else { return }
        let chars = lines[l]
        if chars.isEmpty {
            line = l; col = 0; anchor = (l, 0)
            return
        }
        func isWord(_ ch: Character) -> Bool {
            ch.isLetter || ch.isNumber || ch == "_"
        }
        var start = min(max(c, 0), chars.count - 1)
        if !isWord(chars[start]) && start > 0 && isWord(chars[start - 1]) {
            start -= 1
        }
        if isWord(chars[start]) {
            while start > 0 && isWord(chars[start - 1]) { start -= 1 }
            var end = start
            while end < chars.count && isWord(chars[end]) { end += 1 }
            line = l
            anchor = (l, start)
            col = end
        } else {
            line = l
            anchor = (l, start)
            col = start + 1
        }
        ensureVisible()
    }

    func selectLine(_ l: Int) {
        guard l >= 0 && l < lines.count else { return }
        line = l
        anchor = (l, 0)
        col = lineLength(l)
        ensureVisible()
    }

    func selectAll() {
        anchor = (0, 0)
        line = lines.count - 1
        col = lineLength(line)
        ensureVisible()
    }

    func ensureVisible() {
        if line < scrollLine { scrollLine = line }
        if line >= scrollLine + viewHeight { scrollLine = max(0, line - viewHeight + 1) }
        if col < scrollCol { scrollCol = col }
        if col >= scrollCol + viewWidth { scrollCol = max(0, col - viewWidth + 1) }
        if scrollLine + viewHeight > lines.count && lines.count > viewHeight {
            scrollLine = lines.count - viewHeight
        }
        if scrollLine < 0 { scrollLine = 0 }
        if scrollCol < 0 { scrollCol = 0 }
    }

    // MARK: - Search

    private func findInLine(_ chars: [Character], _ needle: [Character], from: Int) -> Int? {
        guard !needle.isEmpty else { return nil }
        if chars.count < needle.count { return nil }
        let start = min(max(from, 0), chars.count)
        if start + needle.count > chars.count { return nil }
        for i in start...(chars.count - needle.count) {
            var ok = true
            for j in 0..<needle.count where chars[i + j] != needle[j] {
                ok = false
                break
            }
            if ok { return i }
        }
        return nil
    }

    func find(_ needle: String, fromStart: Bool = false) -> Bool {
        let n = Array(needle)
        guard !n.isEmpty else { return false }
        var startLine = line
        var startCol = col
        if fromStart {
            startLine = 0
            startCol = 0
        } else if hasSelection, let (_, e) = selection {
            startLine = e.0
            startCol = e.1
        }
        for l in startLine..<lines.count {
            let from = l == startLine ? startCol : 0
            if let c = findInLine(lines[l], n, from: from) {
                anchor = nil
                line = l
                col = c
                anchor = (l, c)
                col = c + n.count
                ensureVisible()
                return true
            }
        }
        // wrap around, including the part of the starting line before the caret
        for l in 0...startLine where l < lines.count {
            guard let c = findInLine(lines[l], n, from: 0) else { continue }
            if l == startLine && c >= startCol { continue }
            anchor = nil
            line = l
            col = c
            anchor = (l, c)
            col = c + n.count
            ensureVisible()
            return true
        }
        return false
    }

    func replaceAll(_ needle: String, with replacement: String) -> Int {
        let n = Array(needle)
        guard !n.isEmpty else { return 0 }
        var count = 0
        var l = 0
        while l < lines.count {
            var i = 0
            while i + n.count <= lines[l].count {
                var match = true
                for j in 0..<n.count where lines[l][i + j] != n[j] { match = false; break }
                if match {
                    if count == 0 { pushUndo() }
                    lines[l].replaceSubrange(i..<(i + n.count), with: Array(replacement))
                    count += 1
                    i += replacement.count
                } else {
                    i += 1
                }
            }
            l += 1
        }
        if count > 0 {
            modified = true
            line = min(line, lines.count - 1)
            col = min(col, lineLength(line))
        }
        return count
    }

    // MARK: - File

    func text() -> String {
        lines.map { String($0) }.joined(separator: "\n")
    }

    @discardableResult
    func save(to url: URL? = nil) -> Bool {
        if let url = url { fileURL = url }
        guard let target = fileURL else { return false }
        do {
            try text().write(to: target, atomically: true, encoding: .utf8)
            modified = false
            return true
        } catch {
            return false
        }
    }
}
