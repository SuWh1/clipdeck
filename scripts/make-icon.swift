import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources", isDirectory: true)
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    let red = CGFloat((hex >> 16) & 0xFF) / 255
    let green = CGFloat((hex >> 8) & 0xFF) / 255
    let blue = CGFloat(hex & 0xFF) / 255
    return CGColor(colorSpace: sRGB, components: [red, green, blue, alpha])!
}

func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func fill(_ context: CGContext, _ path: CGPath, _ fillColor: CGColor) {
    context.addPath(path)
    context.setFillColor(fillColor)
    context.fillPath()
}

func drawIcon(_ context: CGContext) {
    let body = roundedRect(CGRect(x: 100, y: 100, width: 824, height: 824), radius: 186)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.28))
    fill(context, body, color(0x111114))
    context.restoreGState()

    context.saveGState()
    context.addPath(body)
    context.clip()
    let background = CGGradient(colorsSpace: sRGB, colors: [color(0x2C2C30), color(0x111114)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.restoreGState()

    let front = CGRect(x: 262, y: 322, width: 440, height: 310)
    fill(context, roundedRect(front.offsetBy(dx: 60, dy: 70), radius: 56), color(0xFFFFFF, 0.3))
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -8), blur: 22, color: color(0x000000, 0.22))
    fill(context, roundedRect(front, radius: 56), color(0xFFFFFF))
    context.restoreGState()
}

func render(pixels: Int) -> CGImage {
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                            space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    drawIcon(context)
    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("Clipdeck-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try writePNG(render(pixels: size), to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try writePNG(render(pixels: size * 2), to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
try writePNG(render(pixels: 1024), to: outputDirectory.appendingPathComponent("AppIcon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", outputDirectory.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil failed\n".utf8))
    exit(1)
}
print("Wrote \(outputDirectory.path)/AppIcon.icns")
