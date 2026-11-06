import AppKit

let destination = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
NSColor(srgbRed: 0.10, green: 0.46, blue: 0.40, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 184, yRadius: 184).fill()
NSColor(srgbRed: 0.98, green: 0.98, blue: 0.95, alpha: 1).setStroke()
let body = NSBezierPath(roundedRect: NSRect(x: 260, y: 256, width: 504, height: 520), xRadius: 76, yRadius: 76)
body.lineWidth = 34
body.stroke()
let display = NSBezierPath(roundedRect: NSRect(x: 374, y: 600, width: 276, height: 96), xRadius: 24, yRadius: 24)
display.lineWidth = 28
display.stroke()
let mark = NSBezierPath()
mark.move(to: NSPoint(x: 482, y: 648)); mark.line(to: NSPoint(x: 542, y: 648))
mark.lineWidth = 18; mark.lineCapStyle = .round; mark.stroke()
image.unlockFocus()
guard let tiff=image.tiffRepresentation, let bitmap=NSBitmapImageRep(data:tiff), let png=bitmap.representation(using:.png,properties:[:]) else {fatalError("PNG generation failed")}
try png.write(to:URL(fileURLWithPath:destination))
