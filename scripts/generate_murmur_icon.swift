import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("murmur/Murmur/Resources", isDirectory: true)
let iconset = resources.appendingPathComponent("Murmur.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let sizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSGraphicsContext.current?.imageInterpolation = .high

    NSColor.clear.setFill()
    rect.fill()

    let inset = size * 0.075
    let baseRect = rect.insetBy(dx: inset, dy: inset)
    let corner = size * 0.22
    let basePath = NSBezierPath(roundedRect: baseRect, xRadius: corner, yRadius: corner)

    let baseGradient = NSGradient(colors: [
        color(6, 6, 8),
        color(30, 30, 34),
        color(0, 0, 0)
    ])!
    baseGradient.draw(in: basePath, angle: 135)

    let glowRect = NSRect(
        x: size * 0.12,
        y: size * 0.36,
        width: size * 0.76,
        height: size * 0.48
    )
    let glowPath = NSBezierPath(ovalIn: glowRect)
    NSGraphicsContext.saveGraphicsState()
    glowPath.setClip()
    NSGradient(colors: [
        color(255, 58, 150, 0.46),
        color(255, 255, 255, 0.16),
        color(255, 255, 255, 0.0)
    ])!.draw(in: glowPath, relativeCenterPosition: NSPoint(x: -0.18, y: 0.12))
    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.24).setStroke()
    basePath.lineWidth = max(1.0, size * 0.012)
    basePath.stroke()

    let innerRect = baseRect.insetBy(dx: size * 0.12, dy: size * 0.16)
    let lineWidth = max(3.0, size * 0.055)
    let mPath = NSBezierPath()
    mPath.lineCapStyle = .round
    mPath.lineJoinStyle = .round
    mPath.lineWidth = lineWidth

    let yMid = innerRect.midY
    let amp = innerRect.height * 0.30
    let points = [
        NSPoint(x: innerRect.minX, y: yMid - amp * 0.82),
        NSPoint(x: innerRect.minX + innerRect.width * 0.17, y: yMid + amp * 0.86),
        NSPoint(x: innerRect.minX + innerRect.width * 0.33, y: yMid - amp * 0.52),
        NSPoint(x: innerRect.minX + innerRect.width * 0.50, y: yMid + amp * 0.82),
        NSPoint(x: innerRect.minX + innerRect.width * 0.67, y: yMid - amp * 0.52),
        NSPoint(x: innerRect.minX + innerRect.width * 0.83, y: yMid + amp * 0.86),
        NSPoint(x: innerRect.maxX, y: yMid - amp * 0.82)
    ]
    mPath.move(to: points[0])
    for idx in 1..<points.count {
        mPath.line(to: points[idx])
    }

    NSGraphicsContext.saveGraphicsState()
    NSShadow().apply {
        $0.shadowColor = color(255, 58, 150, 0.62)
        $0.shadowBlurRadius = size * 0.026
        $0.shadowOffset = .zero
    }
    color(250, 250, 252).setStroke()
    mPath.stroke()
    NSGraphicsContext.restoreGraphicsState()

    let dotDiameter = size * 0.14
    let dotRect = NSRect(
        x: baseRect.maxX - dotDiameter * 1.55,
        y: baseRect.maxY - dotDiameter * 1.55,
        width: dotDiameter,
        height: dotDiameter
    )
    let dotGlow = NSBezierPath(ovalIn: dotRect.insetBy(dx: -dotDiameter * 0.42, dy: -dotDiameter * 0.42))
    color(255, 58, 150, 0.26).setFill()
    dotGlow.fill()
    let dot = NSBezierPath(ovalIn: dotRect)
    color(255, 58, 150).setFill()
    dot.fill()
    color(255, 255, 255, 0.72).setStroke()
    dot.lineWidth = max(1, size * 0.006)
    dot.stroke()

    let shineRect = NSRect(x: baseRect.minX, y: baseRect.midY, width: baseRect.width, height: baseRect.height / 2)
    let shine = NSBezierPath(roundedRect: shineRect, xRadius: corner, yRadius: corner)
    NSColor.white.withAlphaComponent(0.06).setFill()
    shine.fill()

    return image
}

extension NSShadow {
    func apply(_ configure: (NSShadow) -> Void) {
        configure(self)
        set()
    }
}

for (name, size) in sizes {
    let image = drawIcon(size: size)
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        fatalError("Could not render \(name)")
    }
    try png.write(to: iconset.appendingPathComponent(name))
}

let preview = drawIcon(size: 1024)
if let tiff = preview.tiffRepresentation,
   let bitmap = NSBitmapImageRep(data: tiff),
   let png = bitmap.representation(using: .png, properties: [:]) {
    try png.write(to: resources.appendingPathComponent("MurmurIcon-1024.png"))
}
