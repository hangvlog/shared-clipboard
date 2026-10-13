import AppKit

// Vector source for every macOS icon size; no image tooling dependencies.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let iconset = output.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func line(_ points: [NSPoint], width: CGFloat, color: NSColor) {
    let path = NSBezierPath()
    path.move(to: points[0])
    for point in points.dropFirst() { path.line(to: point) }
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    color.setStroke()
    path.stroke()
}

func clipboard(template: Bool) {
    let white = template ? NSColor.black : color(1, 1, 1, 0.98)
    let board = rounded(NSRect(x: 278, y: 235, width: 468, height: 544), 70)
    if !template {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = color(0.02, 0.1, 0.4, 0.3)
        shadow.shadowBlurRadius = 25
        shadow.shadowOffset = NSSize(width: 0, height: -14)
        shadow.set()
        color(0.9, 0.98, 1, 0.16).setFill()
        board.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    white.setStroke()
    board.lineWidth = 34
    board.stroke()
    let clip = rounded(NSRect(x: 410, y: 738, width: 204, height: 82), 36)
    white.setFill()
    clip.fill()

    // Two opposing arrows communicate sharing at Dock and Finder sizes.
    line([NSPoint(x: 377, y: 566), NSPoint(x: 645, y: 566)], width: 34, color: white)
    line([NSPoint(x: 587, y: 624), NSPoint(x: 645, y: 566), NSPoint(x: 587, y: 508)], width: 34, color: white)
    line([NSPoint(x: 647, y: 426), NSPoint(x: 379, y: 426)], width: 34, color: white)
    line([NSPoint(x: 437, y: 484), NSPoint(x: 379, y: 426), NSPoint(x: 437, y: 368)], width: 34, color: white)
}

func render(pixels: Int, destination: URL, template: Bool = false) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels,
        pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

    if !template {
        let tile = rounded(NSRect(x: 92, y: 92, width: 840, height: 840), 192)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = color(0.02, 0.1, 0.3, 0.28)
        shadow.shadowBlurRadius = 28
        shadow.shadowOffset = NSSize(width: 0, height: -16)
        shadow.set()
        color(0.12, 0.4, 0.88).setFill()
        tile.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(colors: [color(0.16, 0.38, 0.9), color(0.05, 0.62, 0.91), color(0.32, 0.85, 0.94)])!
            .draw(in: tile, angle: 65)

        NSGraphicsContext.saveGraphicsState()
        tile.addClip()
        let light = NSBezierPath(ovalIn: NSRect(x: -180, y: 510, width: 1310, height: 660))
        NSGradient(starting: color(1, 1, 1, 0.02), ending: color(1, 1, 1, 0.24))!
            .draw(in: light, angle: 90)
        NSGraphicsContext.restoreGraphicsState()
        color(1, 1, 1, 0.35).setStroke()
        tile.lineWidth = 3
        tile.stroke()
    } else {
        // Fill the menu-bar canvas while retaining the same silhouette.
        context.cgContext.translateBy(x: -225, y: -165)
        context.cgContext.scaleBy(x: 1.45, y: 1.45)
    }
    clipboard(template: template)
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: destination)
}

for points in [16, 32, 128, 256, 512] {
    try render(pixels: points, destination: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(pixels: points * 2, destination: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
try render(pixels: 36, destination: output.appendingPathComponent("StatusIcon.png"), template: true)
