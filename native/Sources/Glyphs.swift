import Foundation

/// The 8x16 bitmap glyphs, pre-rendered from PxPlus IBM VGA8 by
/// tools/make_glyphs.py. No font file is needed at runtime.
final class GlyphSet {
    let cellW: Int
    let cellH: Int
    let cols: Int
    let rows: Int
    let atlasW: Int
    let masks: [UInt8]
    private let index: [Character: Int]
    let fallback: Int

    private struct Meta: Decodable {
        let cellW: Int
        let cellH: Int
        let cols: Int
        let rows: Int
        let chars: [String]
    }

    init(binURL: URL, jsonURL: URL) throws {
        let meta = try JSONDecoder().decode(Meta.self, from: Data(contentsOf: jsonURL))
        cellW = meta.cellW
        cellH = meta.cellH
        cols = meta.cols
        rows = meta.rows
        atlasW = meta.cols * meta.cellW
        masks = [UInt8](try Data(contentsOf: binURL))
        var map: [Character: Int] = [:]
        map.reserveCapacity(meta.chars.count)
        for (i, s) in meta.chars.enumerated() {
            if let ch = s.first, s.count == 1 { map[ch] = i }
        }
        index = map
        fallback = map["?"] ?? 0
    }

    func glyphIndex(for ch: Character) -> Int {
        index[ch] ?? fallback
    }

    func maskOffset(for glyph: Int) -> Int {
        let cell = glyph
        let cx = cell % cols
        let cy = cell / cols
        return cy * cellH * atlasW + cx * cellW
    }
}
