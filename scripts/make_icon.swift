import AppKit
import Foundation

let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let bounds = NSRect(x: 0, y: 0, width: 1024, height: 1024)
NSGradient(starting: NSColor(srgbRed: 1, green: 0.94, blue: 0.93, alpha: 1), ending: NSColor(srgbRed: 0.89, green: 0.56, blue: 0.65, alpha: 1))!.draw(in: bounds, angle: -65)
let petalColor = NSColor(srgbRed: 1, green: 0.98, blue: 0.96, alpha: 0.43)
for i in 0..<5 {
    NSGraphicsContext.saveGraphicsState()
    let transform = AffineTransform(translationByX: 760, byY: 785)
    (transform as NSAffineTransform).concat()
    let rotation = NSAffineTransform()
    rotation.rotate(byDegrees: CGFloat(i) * 72)
    rotation.concat()
    petalColor.setFill()
    NSBezierPath(ovalIn: NSRect(x: -55, y: 10, width: 110, height: 185)).fill()
    NSGraphicsContext.restoreGraphicsState()
}
let left = NSBezierPath()
left.move(to: NSPoint(x: 210, y: 680))
left.curve(to: NSPoint(x: 505, y: 605), controlPoint1: NSPoint(x: 315, y: 710), controlPoint2: NSPoint(x: 450, y: 672))
left.line(to: NSPoint(x: 505, y: 295))
left.curve(to: NSPoint(x: 210, y: 355), controlPoint1: NSPoint(x: 420, y: 360), controlPoint2: NSPoint(x: 305, y: 385))
left.close()
NSColor(srgbRed: 1, green: 0.99, blue: 0.975, alpha: 1).setFill()
left.fill()
let right = NSBezierPath()
right.move(to: NSPoint(x: 519, y: 605))
right.curve(to: NSPoint(x: 814, y: 680), controlPoint1: NSPoint(x: 575, y: 672), controlPoint2: NSPoint(x: 709, y: 710))
right.line(to: NSPoint(x: 814, y: 355))
right.curve(to: NSPoint(x: 519, y: 295), controlPoint1: NSPoint(x: 719, y: 385), controlPoint2: NSPoint(x: 604, y: 360))
right.close()
NSColor(srgbRed: 1, green: 0.94, blue: 0.925, alpha: 1).setFill()
right.fill()
NSColor(srgbRed: 0.71, green: 0.30, blue: 0.41, alpha: 0.7).setStroke()
for offset in [0.0, 60.0, 120.0] {
    let line = NSBezierPath()
    line.lineWidth = 14
    line.lineCapStyle = .round
    line.move(to: NSPoint(x: 270, y: 590 - offset))
    line.curve(to: NSPoint(x: 445, y: 550 - offset), controlPoint1: NSPoint(x: 340, y: 598 - offset), controlPoint2: NSPoint(x: 390, y: 575 - offset))
    line.stroke()
}
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
let path = "Manabi/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
print("Created Manabi icon")
