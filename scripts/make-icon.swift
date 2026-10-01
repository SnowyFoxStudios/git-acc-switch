// Draws the app icon and writes Resources/AppIcon.icns. Run with: swift scripts/make-icon.swift
import AppKit

let canvas: CGFloat = 1024

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: size / canvas, y: size / canvas)

    // Standard macOS icon grid: an 824pt rounded square centred on the 1024pt canvas.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(tilePath)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [NSColor(srgbRed: 0.42, green: 0.27, blue: 0.93, alpha: 1).cgColor,
                 NSColor(srgbRed: 0.10, green: 0.12, blue: 0.30, alpha: 1).cgColor] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: tile.minX, y: tile.maxY),
                           end: CGPoint(x: tile.maxX, y: tile.minY), options: [])
    ctx.restoreGState()

    // Switch arrows around a person: "change account".
    symbol("arrow.triangle.2.circlepath", pointSize: 560, alpha: 0.95, center: CGPoint(x: 512, y: 512))
    symbol("person.fill", pointSize: 230, alpha: 1, center: CGPoint(x: 512, y: 506))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func symbol(_ name: String, pointSize: CGFloat, alpha: CGFloat, center: CGPoint) {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        .applying(.init(paletteColors: [NSColor.white.withAlphaComponent(alpha)]))
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else { fatalError("missing symbol \(name)") }
    let s = image.size
    image.draw(in: CGRect(x: center.x - s.width / 2, y: center.y - s.height / 2, width: s.width, height: s.height))
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let png = drawIcon(size: CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try png.write(to: iconset.appendingPathComponent(name))
    }
}

let output = root.appendingPathComponent("Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote \(output.path)")
