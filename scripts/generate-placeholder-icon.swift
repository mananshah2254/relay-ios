// Temporary vector-drawn development icon. Replace before final branding.
import AppKit
import Foundation

let output = CommandLine.arguments.dropFirst().first ?? "iOS/Relay/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
let size = 1024
let space = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                              space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("Cannot allocate icon") }
let colors = [CGColor(red: 0.28, green: 0.25, blue: 0.67, alpha: 1), CGColor(red: 0.46, green: 0.41, blue: 0.86, alpha: 1)] as CFArray
let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 1024, y: 1024), options: [])
context.setStrokeColor(CGColor(gray: 1, alpha: 0.09))
context.setLineWidth(2)
for radius in stride(from: 190.0, through: 720.0, by: 135.0) {
    context.strokeEllipse(in: CGRect(x: 512 - radius, y: 512 - radius, width: radius * 2, height: radius * 2))
}
let plane = CGMutablePath()
plane.move(to: CGPoint(x: 254, y: 533))
plane.addLine(to: CGPoint(x: 754, y: 754))
plane.addLine(to: CGPoint(x: 539, y: 252))
plane.addLine(to: CGPoint(x: 462, y: 462))
plane.closeSubpath()
context.addPath(plane)
context.setFillColor(CGColor(red: 1, green: 0.98, blue: 0.91, alpha: 1))
context.fillPath()
context.setStrokeColor(CGColor(red: 0.35, green: 0.31, blue: 0.73, alpha: 1))
context.setLineWidth(18)
context.setLineCap(.round)
context.move(to: CGPoint(x: 465, y: 465))
context.addLine(to: CGPoint(x: 662, y: 664))
context.strokePath()
guard let image = context.makeImage(), let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { fatalError("Cannot encode icon") }
let url = URL(fileURLWithPath: output)
try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
try png.write(to: url, options: .atomic)
print("Generated development icon at \(output)")

