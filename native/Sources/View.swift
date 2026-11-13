import AppKit
import CoreGraphics

final class CharacterView: NSView {
    let state: AppState
    let renderer: Renderer
    private let screen: Screen

    init(state: AppState, renderer: Renderer) {
        self.state = state
        self.renderer = renderer
        self.screen = Screen(cols: 80, rows: 25)
        super.init(frame: NSRect(x: 0, y: 0, width: 960, height: 600))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(bounds)
        state.render(into: screen)
        guard let image = renderer.makeImage(screen) else { return }
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
        ctx.draw(image, in: imageRect())
    }

    private func imageRect() -> CGRect {
        // Scale by whole device pixels, never by a fraction: a 3.37x nearest
        // neighbour stretch would make some glyphs thicker than others.
        let backing = window?.backingScaleFactor ?? 2
        let pixelsW = bounds.width * backing
        let pixelsH = bounds.height * backing
        let factor = max(1, Int(min(pixelsW / CGFloat(renderer.width),
                                    pixelsH / CGFloat(renderer.height))))
        let w = CGFloat(renderer.width * factor) / backing
        let h = CGFloat(renderer.height * factor) / backing
        return CGRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
    }

    private func cell(at event: NSEvent) -> (Int, Int)? {
        let p = convert(event.locationInWindow, from: nil)
        let r = imageRect()
        guard r.contains(p) else { return nil }
        let fx = Double((p.x - r.minX) / r.width)
        let fy = Double((p.y - r.minY) / r.height)
        let x = Int(fx * 80)
        let y = Int((1 - fy) * 25)
        guard x >= 0, x < 80, y >= 0, y < 25 else { return nil }
        return (x, y)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        guard let (x, y) = cell(at: event) else { return }
        state.mouseMoved(x: x, y: y)
        setCursor(for: state.cursorKind(x: x, y: y))
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if let (x, y) = cell(at: event) {
            state.mouseMoved(x: x, y: y)
            state.mouseDown(x: x, y: y, shift: event.modifierFlags.contains(.shift),
                            clicks: event.clickCount)
            needsDisplay = true
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let (x, y) = cell(at: event) else { return }
        state.rightClick(x: x, y: y)
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        guard let (x, y) = cell(at: event) else { return }
        if event.phase == .began {
            state.resetScrollAccumulators()
        }
        let pointsPerLine = Double(imageRect().height) / 25.0
        state.scrollWheel(x: x, y: y,
                          dy: event.scrollingDeltaY,
                          dx: event.scrollingDeltaX,
                          precise: event.hasPreciseScrollingDeltas,
                          pointsPerLine: pointsPerLine)
        needsDisplay = true
    }

    private func setCursor(for kind: CursorKind) {
        switch kind {
        case .arrow: NSCursor.arrow.set()
        case .ibeam: NSCursor.iBeam.set()
        case .hand: NSCursor.pointingHand.set()
        case .resize: NSCursor.resizeUpDown.set()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if let (x, y) = cell(at: event) {
            state.mouseDragged(x: x, y: y)
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        state.mouseUp()
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        let key = KeyEvent(keyCode: event.keyCode,
                           chars: event.charactersIgnoringModifiers ?? "",
                           shift: event.modifierFlags.contains(.shift),
                           option: event.modifierFlags.contains(.option),
                           command: event.modifierFlags.contains(.command),
                           control: event.modifierFlags.contains(.control))
        if state.wantsRawKey(key) {
            state.keyDown(key)
            needsDisplay = true
        } else {
            interpretKeyEvents([event])
        }
    }

    override func insertText(_ insertString: Any) {
        let text: String
        if let s = insertString as? String {
            text = s
        } else if let a = insertString as? NSAttributedString {
            text = a.string
        } else {
            return
        }
        guard !text.isEmpty else { return }
        state.insertText(text)
        needsDisplay = true
    }
}
