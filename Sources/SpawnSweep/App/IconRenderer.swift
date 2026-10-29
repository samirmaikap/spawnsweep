import SwiftUI
import AppKit

/// Renders the app icon (the AppMark: moon on a deep sage clay tile) to a 1024 px PNG. Used by scripts/bundle.sh.
enum IconRenderer {
    static func render(to path: String) {
        MainActor.assumeIsolated {
            // macOS icon grid: an 824 px tile centered on a 1024 px canvas, with room for its shadow.
            let view = AppMark(size: 824)
                .shadow(color: .black.opacity(0.28), radius: 24, y: 12)
                .frame(width: 1024, height: 1024)
            .environment(\.colorScheme, .light)
            let r = ImageRenderer(content: view)
            r.scale = 1
            guard let img = r.nsImage, let tiff = img.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }
}
