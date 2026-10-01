// Draws the app icon and writes Resources/AppIcon.icns. Run with: swift scripts/make-icon.swift
// Drawn from plain shapes only: SF Symbols may not be used in app icons.
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

    // Two overlapping accounts above a swap arrow.
    let ink = NSColor(srgbRed: 0.30, green: 0.20, blue: 0.68, alpha: 1).cgColor
    let back = (center: CGPoint(x: 612, y: 612), radius: CGFloat(150))
    let front = (center: CGPoint(x: 420, y: 566), radius: CGFloat(178))

    // The back account, with a gap cut around the front one so they read as separate.
    ctx.saveGState()
    ctx.addEllipse(in: circle(back.center, back.radius))
    ctx.addEllipse(in: circle(front.center, front.radius + 22))
    ctx.clip(using: .evenOdd)
    avatar(ctx, back.center, back.radius, disc: NSColor.white.withAlphaComponent(0.55).cgColor,
           person: ink.copy(alpha: 0.75)!)
    ctx.restoreGState()
    avatar(ctx, front.center, front.radius, disc: NSColor.white.cgColor, person: ink)

    // ⇄ below them.
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setFillColor(NSColor.white.cgColor)
    arrow(ctx, from: CGPoint(x: 330, y: 318), to: CGPoint(x: 700, y: 318))
    arrow(ctx, from: CGPoint(x: 694, y: 222), to: CGPoint(x: 324, y: 222))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func circle(_ c: CGPoint, _ r: CGFloat) -> CGRect {
    CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
}

/// A disc with a head-and-shoulders silhouette inside it.
func avatar(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, disc: CGColor, person: CGColor) {
    ctx.saveGState()
    ctx.addEllipse(in: circle(c, r))
    ctx.clip()
    ctx.setFillColor(disc)
    ctx.fill(circle(c, r))
    ctx.setFillColor(person)
    ctx.fillEllipse(in: circle(CGPoint(x: c.x, y: c.y + r * 0.22), r * 0.30))
    ctx.fillEllipse(in: CGRect(x: c.x - r * 0.62, y: c.y - r * 1.02, width: r * 1.24, height: r * 0.92))
    ctx.restoreGState()
}

/// A thick line with a triangular head at `to`.
func arrow(_ ctx: CGContext, from: CGPoint, to: CGPoint) {
    let dir: CGFloat = to.x > from.x ? 1 : -1
    let head: CGFloat = 70
    ctx.setLineWidth(40)
    ctx.setLineCap(.round)
    ctx.move(to: from)
    ctx.addLine(to: CGPoint(x: to.x - dir * head * 0.6, y: to.y))
    ctx.strokePath()
    ctx.move(to: to)
    ctx.addLine(to: CGPoint(x: to.x - dir * head, y: to.y + head * 0.72))
    ctx.addLine(to: CGPoint(x: to.x - dir * head, y: to.y - head * 0.72))
    ctx.closePath()
    ctx.fillPath()
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
