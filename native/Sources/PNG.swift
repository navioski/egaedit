import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum PNG {
    static func write(_ image: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL,
                                                         UTType.png.identifier as CFString,
                                                         1, nil) else {
            print("PNG: cannot create destination at \(url.path)")
            return
        }
        CGImageDestinationAddImage(dest, image, nil)
        if !CGImageDestinationFinalize(dest) {
            print("PNG: finalize failed")
        }
    }
}
