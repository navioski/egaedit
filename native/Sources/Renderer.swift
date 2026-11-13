import Foundation
import CoreGraphics

/// Composes a Screen into a 1:1 pixel image: 8x16 pixels per character cell.
final class Renderer {
    let glyphs: GlyphSet
    let width: Int
    let height: Int
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    init(glyphs: GlyphSet, cols: Int, rows: Int) {
        self.glyphs = glyphs
        width = cols * glyphs.cellW
        height = rows * glyphs.cellH
    }

    func makeImage(_ screen: Screen) -> CGImage? {
        var pixels = [UInt32](repeating: 0xFF000000, count: width * height)

        pixels.withUnsafeMutableBufferPointer { buf in
            let cw = glyphs.cellW
            let ch = glyphs.cellH
            let atlasW = glyphs.atlasW
            let masks = glyphs.masks

            for cy in 0..<screen.rows {
                for cx in 0..<screen.cols {
                    let cell = screen.cells[cy * screen.cols + cx]
                    let bg = pixel(cell.bg)
                    let fg = pixel(cell.fg)
                    let originX = cx * cw
                    let originY = cy * ch

                    for y in 0..<ch {
                        let row = (originY + y) * width + originX
                        for x in 0..<cw {
                            buf[row + x] = bg
                        }
                    }

                    let glyph = glyphs.glyphIndex(for: cell.ch)
                    if glyph == 0 { continue }
                    let moff = glyphs.maskOffset(for: glyph)
                    for y in 0..<ch {
                        let mrow = moff + y * atlasW
                        let prow = (originY + y) * width + originX
                        for x in 0..<cw where masks[mrow + x] != 0 {
                            buf[prow + x] = fg
                        }
                    }
                }
            }
        }

        guard let provider = CGDataProvider(data: Data(bytes: pixels, count: pixels.count * 4) as CFData) else {
            return nil
        }
        return CGImage(width: width,
                       height: height,
                       bitsPerComponent: 8,
                       bitsPerPixel: 32,
                       bytesPerRow: width * 4,
                       space: colorSpace,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                       provider: provider,
                       decode: nil,
                       shouldInterpolate: false,
                       intent: .defaultIntent)
    }

    private func pixel(_ c: RGB) -> UInt32 {
        let r = (c >> 16) & 0xFF
        let g = (c >> 8) & 0xFF
        let b = c & 0xFF
        // The bitmap is interpreted as BGRA (alpha in the high byte).
        return (0xFF << 24) | (b << 16) | (g << 8) | r
    }
}
