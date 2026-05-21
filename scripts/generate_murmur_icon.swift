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

func handFont(size: CGFloat) -> NSFont {
    let names = [
        "MarkerFelt-Wide",
        "MarkerFelt-Thin",
        "ChalkboardSE-Bold",
        "Noteworthy-Bold",
        "ArialRoundedMTBold"
    ]
    for name in names {
        if let font = NSFont(name: name, size: size) {
            return font
        }
    }
    return NSFont.systemFont(ofSize: size, weight: .black)
}

func drawStroke(_ path: NSBezierPath, color strokeColor: NSColor, width: CGFloat) {
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.lineWidth = width
    strokeColor.setStroke()
    path.stroke()
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
    let corner = size * 0.20
    let basePath = NSBezierPath(roundedRect: baseRect, xRadius: corner, yRadius: corner)

    let baseGradient = NSGradient(colors: [
        color(255, 253, 247),
        color(247, 244, 238),
        color(255, 255, 252)
    ])!
    baseGradient.draw(in: basePath, angle: 90)

    NSColor.black.withAlphaComponent(0.08).setStroke()
    basePath.lineWidth = max(1.0, size * 0.01)
    basePath.stroke()

    let text = "M"
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    var fontSize = size * 0.58
    var font = handFont(size: fontSize)
    var attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color(5, 5, 5),
        .paragraphStyle: paragraph,
        .kern: 0
    ]
    var textSize = text.size(withAttributes: attributes)
    let maxWidth = baseRect.width * 0.70
    let maxHeight = baseRect.height * 0.68
    while (textSize.width > maxWidth || textSize.height > maxHeight) && fontSize > size * 0.10 {
        fontSize -= size * 0.006
        font = handFont(size: fontSize)
        attributes[.font] = font
        textSize = text.size(withAttributes: attributes)
    }

    let textRect = NSRect(
        x: baseRect.midX - maxWidth / 2,
        y: baseRect.midY - textSize.height * 0.54,
        width: maxWidth,
        height: textSize.height * 1.20
    )

    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: textRect.midX, yBy: textRect.midY)
    transform.rotate(byDegrees: -1.5)
    transform.translateX(by: -textRect.midX, yBy: -textRect.midY)
    transform.concat()
    text.draw(in: textRect, withAttributes: attributes)
    NSGraphicsContext.restoreGraphicsState()

    let dotDiameter = size * 0.075
    let dot = NSBezierPath(ovalIn: NSRect(
        x: baseRect.maxX - baseRect.width * 0.18,
        y: baseRect.minY + baseRect.height * 0.24,
        width: dotDiameter,
        height: dotDiameter
    ))
    color(255, 60, 155).setFill()
    dot.fill()

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
