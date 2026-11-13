import Foundation

typealias RGB = UInt32

enum EGA {
    static let black: RGB      = 0x000000
    static let blue: RGB       = 0x0000AA
    static let green: RGB      = 0x00AA00
    static let cyan: RGB       = 0x00AAAA
    static let red: RGB        = 0xAA0000
    static let magenta: RGB    = 0xAA00AA
    static let brown: RGB      = 0xAA5500
    static let gray: RGB       = 0xAAAAAA
    static let darkGray: RGB   = 0x555555
    static let lightBlue: RGB  = 0x5555FF
    static let lightGreen: RGB = 0x55FF55
    static let lightCyan: RGB  = 0x55FFFF
    static let lightRed: RGB   = 0xFF5555
    static let lightMagenta: RGB = 0xFF55FF
    static let yellow: RGB     = 0xFFFF55
    static let white: RGB      = 0xFFFFFF
}

struct Cell {
    var ch: Character = " "
    var fg: RGB = EGA.gray
    var bg: RGB = EGA.blue
}

struct CellRect: Equatable {
    var x: Int
    var y: Int
    var w: Int
    var h: Int

    init(x: Int, y: Int, w: Int, h: Int) {
        self.x = x; self.y = y; self.w = w; self.h = h
    }

    var maxX: Int { x + w - 1 }
    var maxY: Int { y + h - 1 }

    func contains(_ px: Int, _ py: Int) -> Bool {
        px >= x && px <= maxX && py >= y && py <= maxY
    }

    func inset(_ dx: Int, _ dy: Int) -> CellRect {
        CellRect(x: x + dx, y: y + dy, w: w - 2 * dx, h: h - 2 * dy)
    }
}

final class Screen {
    let cols: Int
    let rows: Int
    var cells: [Cell]

    init(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
        cells = Array(repeating: Cell(), count: cols * rows)
    }

    func clear(_ ch: Character = " ", fg: RGB = EGA.gray, bg: RGB = EGA.blue) {
        cells = Array(repeating: Cell(ch: ch, fg: fg, bg: bg), count: cols * rows)
    }

    func set(_ x: Int, _ y: Int, _ ch: Character, fg: RGB, bg: RGB) {
        guard x >= 0, y >= 0, x < cols, y < rows else { return }
        cells[y * cols + x] = Cell(ch: ch, fg: fg, bg: bg)
    }

    func put(_ x: Int, _ y: Int, _ text: String, fg: RGB, bg: RGB) {
        var px = x
        for ch in text {
            set(px, y, ch, fg: fg, bg: bg)
            px += 1
        }
    }

    /// Draws text, colouring the character after each '~' as a hotkey.
    func putHot(_ x: Int, _ y: Int, _ text: String, fg: RGB, hot: RGB, bg: RGB, limit: Int = .max) {
        var px = x
        var hotNext = false
        for ch in text {
            guard px - x < limit else { break }
            if ch == "~" { hotNext = true; continue }
            set(px, y, ch, fg: hotNext ? hot : fg, bg: bg)
            hotNext = false
            px += 1
        }
    }

    func fill(_ r: CellRect, _ ch: Character, fg: RGB, bg: RGB) {
        for y in max(0, r.y)...max(0, r.maxY) where y < rows {
            for x in max(0, r.x)...max(0, r.maxX) where x < cols {
                cells[y * cols + x] = Cell(ch: ch, fg: fg, bg: bg)
            }
        }
    }

    func hline(_ x: Int, _ y: Int, _ w: Int, _ ch: Character, fg: RGB, bg: RGB) {
        for i in 0..<w { set(x + i, y, ch, fg: fg, bg: bg) }
    }

    func vline(_ x: Int, _ y: Int, _ h: Int, _ ch: Character, fg: RGB, bg: RGB) {
        for i in 0..<h { set(x, y + i, ch, fg: fg, bg: bg) }
    }

    /// Double-line box, Turbo Vision style.
    func box(_ r: CellRect, fg: RGB, bg: RGB, fill: Bool = true) {
        guard r.w >= 2, r.h >= 2 else { return }
        if fill { self.fill(r, " ", fg: fg, bg: bg) }
        set(r.x, r.y, "╔", fg: fg, bg: bg)
        set(r.maxX, r.y, "╗", fg: fg, bg: bg)
        set(r.x, r.maxY, "╚", fg: fg, bg: bg)
        set(r.maxX, r.maxY, "╝", fg: fg, bg: bg)
        for x in (r.x + 1)..<r.maxX {
            set(x, r.y, "═", fg: fg, bg: bg)
            set(x, r.maxY, "═", fg: fg, bg: bg)
        }
        for y in (r.y + 1)..<r.maxY {
            set(r.x, y, "║", fg: fg, bg: bg)
            set(r.maxX, y, "║", fg: fg, bg: bg)
        }
    }

    /// Single-line box for menus and inputs.
    func thinBox(_ r: CellRect, fg: RGB, bg: RGB, fill: Bool = true) {
        guard r.w >= 2, r.h >= 2 else { return }
        if fill { self.fill(r, " ", fg: fg, bg: bg) }
        set(r.x, r.y, "┌", fg: fg, bg: bg)
        set(r.maxX, r.y, "┐", fg: fg, bg: bg)
        set(r.x, r.maxY, "└", fg: fg, bg: bg)
        set(r.maxX, r.maxY, "┘", fg: fg, bg: bg)
        for x in (r.x + 1)..<r.maxX {
            set(x, r.y, "─", fg: fg, bg: bg)
            set(x, r.maxY, "─", fg: fg, bg: bg)
        }
        for y in (r.y + 1)..<r.maxY {
            set(r.x, y, "│", fg: fg, bg: bg)
            set(r.maxX, y, "│", fg: fg, bg: bg)
        }
    }

    /// One-cell black drop shadow to the right and below.
    func shadow(_ r: CellRect) {
        for y in r.y...r.maxY {
            set(r.maxX + 1, y, " ", fg: EGA.black, bg: EGA.black)
        }
        for x in r.x...r.maxX {
            set(x, r.maxY + 1, " ", fg: EGA.black, bg: EGA.black)
        }
    }

    /// Fills the desktop with the 25% dither pattern.
    func ditherDesktop(width: Int, rows: Int) {
        for y in 0..<rows {
            for x in 0..<width {
                set(x, y, "░", fg: EGA.gray, bg: EGA.blue)
            }
        }
    }
}
