import AppKit
import Foundation

let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    let outer = NSBezierPath(roundedRect: NSRect(x: 70, y: 65, width: 884, height: 884), xRadius: 200, yRadius: 200)
    NSColor(calibratedRed: 0.043, green: 0.039, blue: 0.051, alpha: 1).setFill(); outer.fill()
    let ring = NSBezierPath(ovalIn: NSRect(x: 195, y: 190, width: 634, height: 634))
    NSColor(calibratedRed: 1, green: 0.45, blue: 0.69, alpha: 0.25).setStroke(); ring.lineWidth = 12; ring.stroke()
    NSColor(calibratedRed: 1, green: 0.45, blue: 0.69, alpha: 1).setFill()
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 512, y: 745)); arrow.line(to: NSPoint(x: 315, y: 540))
    arrow.line(to: NSPoint(x: 423, y: 540)); arrow.line(to: NSPoint(x: 423, y: 405))
    arrow.line(to: NSPoint(x: 601, y: 405)); arrow.line(to: NSPoint(x: 601, y: 540))
    arrow.line(to: NSPoint(x: 709, y: 540)); arrow.close(); arrow.fill()
    NSBezierPath(roundedRect: NSRect(x: 423, y: 300, width: 178, height: 58), xRadius: 12, yRadius: 12).fill()
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not render icon") }
    let filenames: [String]
    switch size {
    case 16: filenames = ["icon_16x16.png"]
    case 32: filenames = ["icon_16x16@2x.png", "icon_32x32.png"]
    case 64: filenames = ["icon_32x32@2x.png"]
    case 128: filenames = ["icon_128x128.png"]
    case 256: filenames = ["icon_128x128@2x.png", "icon_256x256.png"]
    case 512: filenames = ["icon_256x256@2x.png", "icon_512x512.png"]
    default: filenames = ["icon_512x512@2x.png"]
    }
    for name in filenames { try png.write(to: URL(fileURLWithPath: destination).appendingPathComponent(name)) }
}
