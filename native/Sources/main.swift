import AppKit
import Foundation

/// `--dump` renders the interface to a PNG without opening a window. It is how
/// the screenshots in docs/ are produced (and how the pixel pipeline is tested).
private func runDump(_ argv: [String]) {
    func value(after flag: String) -> String? {
        guard let i = argv.firstIndex(of: flag), i + 1 < argv.count else { return nil }
        return argv[i + 1]
    }

    guard let outPath = value(after: "--dump") else {
        FileHandle.standardError.write(Data("usage: EGAEdit --dump out.png [--screen main|menu|about|keys|find|replace] [--resources DIR]\n".utf8))
        exit(2)
    }

    let resources: URL
    if let p = value(after: "--resources") {
        resources = URL(fileURLWithPath: p)
    } else if let r = Bundle.main.resourceURL,
              FileManager.default.fileExists(atPath: r.appendingPathComponent("glyphs.bin").path) {
        resources = r
    } else {
        resources = URL(fileURLWithPath: "Resources")
    }

    guard let glyphs = try? GlyphSet(binURL: resources.appendingPathComponent("glyphs.bin"),
                                     jsonURL: resources.appendingPathComponent("glyphs.json")) else {
        FileHandle.standardError.write(Data("cannot load glyph atlas from \(resources.path)\n".utf8))
        exit(1)
    }

    let state = AppState()
    let welcome = (try? String(contentsOf: resources.appendingPathComponent("WELCOME.TXT"), encoding: .utf8))
        ?? "EGA EDIT\n"
    state.newWindow(text: welcome)
    state.activeWindow?.buffer.displayTitle = "WELCOME.TXT"
    state.clockText = "21:00:00"

    switch value(after: "--screen") ?? "main" {
    case "menu":
        state.openMenu(0)
        state.menuCursor = 1
    case "about":
        state.dialog = Dialog.about()
    case "keys":
        state.dialog = Dialog.keys()
    case "find":
        state.dialog = Dialog.find()
    case "replace":
        state.dialog = Dialog.replace()
    default:
        break
    }

    let renderer = Renderer(glyphs: glyphs, cols: 80, rows: 25)
    let screen = Screen(cols: 80, rows: 25)
    state.render(into: screen)
    guard let image = renderer.makeImage(screen) else {
        FileHandle.standardError.write(Data("render failed\n".utf8))
        exit(1)
    }
    PNG.write(image, to: URL(fileURLWithPath: outPath))
    print("wrote \(outPath) \(image.width)x\(image.height)")
}

if CommandLine.arguments.contains("--selftest") {
    SelfTest.run()
    exit(0)
}

if CommandLine.arguments.contains("--dump") {
    runDump(CommandLine.arguments)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
