import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Generates the app and menu bar icons from the sources in Resources/Icons.
// usage (from the repository root): swift scripts/make-icons.swift
//   Resources/Icons/MenuBarIcon-source.png  white shape on transparent (template)
//   Resources/Icons/AppIcon-source.png      1024 px artwork, any background
//   Resources/Icons/GitHubMark-source.svg   Octicons mark-github (MIT)
//   Resources/Icons/AboutIcon-source.png    remote on transparent background
// writes
//   Resources/AboutIcon.png, Resources/AboutIcon@2x.png       (56 pt tall)
//   Resources/MenuBarIcon.png, Resources/MenuBarIcon@2x.png   (18 pt tall, template)
//   Resources/GitHubMark.png, Resources/GitHubMark@2x.png     (16 pt, template)
//   Resources/AppIcon.icns                                     (rounded square, macOS grid)

let root = FileManager.default.currentDirectoryPath
func path(_ relative: String) -> String { root + "/" + relative }

func load(_ relative: String) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path(relative)) as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { fatalError("cannot read \(relative)") }
    return image
}

func save(_ image: CGImage, to absolute: String) {
    guard let out = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: absolute) as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("cannot write \(absolute)") }
    CGImageDestinationAddImage(out, image, nil)
    guard CGImageDestinationFinalize(out) else { fatalError("cannot write \(absolute)") }
}

func context(_ width: Int, _ height: Int) -> CGContext {
    let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    return ctx
}

/// Tight bounding box of the visible (non-transparent) pixels, in top-left image coordinates.
func visibleBounds(of image: CGImage, minAlpha: UInt8 = 8) -> CGRect {
    let w = image.width, h = image.height
    let ctx = context(w, h)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
    let stride = ctx.bytesPerRow
    var minX = w, minY = h, maxX = -1, maxY = -1
    for y in 0..<h {
        for x in 0..<w where data[y * stride + x * 4 + 3] > minAlpha {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    precondition(maxX >= 0, "image is fully transparent")
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

// MARK: menu bar template

let menuSource = load("Resources/Icons/MenuBarIcon-source.png")
let cropped = menuSource.cropping(to: visibleBounds(of: menuSource))!
for (scale, suffix) in [(1, ""), (2, "@2x")] {
    let height = 18 * scale
    let width = Int((Double(cropped.width) * Double(height) / Double(cropped.height)).rounded())
    let ctx = context(width, height)
    ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
    save(ctx.makeImage()!, to: path("Resources/MenuBarIcon\(suffix).png"))
    print("MenuBarIcon\(suffix).png \(width)x\(height)")
}

// MARK: About logo (56 pt tall, transparent padding and faint specks cropped away)

let aboutSource = load("Resources/Icons/AboutIcon-source.png")
let aboutCropped = aboutSource.cropping(to: visibleBounds(of: aboutSource, minAlpha: 96))!
for (scale, suffix) in [(1, ""), (2, "@2x")] {
    let height = 56 * scale
    let width = Int((Double(aboutCropped.width) * Double(height) / Double(aboutCropped.height)).rounded())
    let ctx = context(width, height)
    ctx.draw(aboutCropped, in: CGRect(x: 0, y: 0, width: width, height: height))
    save(ctx.makeImage()!, to: path("Resources/AboutIcon\(suffix).png"))
    print("AboutIcon\(suffix).png \(width)x\(height)")
}

// MARK: GitHub mark for the About section (template, 16 pt)

guard let githubMark = NSImage(contentsOf: URL(fileURLWithPath: path("Resources/Icons/GitHubMark-source.svg")))
else { fatalError("cannot read GitHubMark-source.svg") }
for (scale, suffix) in [(1, ""), (2, "@2x")] {
    let pixels = 16 * scale
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)
    else { fatalError("cannot render GitHubMark") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    githubMark.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: path("Resources/GitHubMark\(suffix).png")))
    print("GitHubMark\(suffix).png \(pixels)x\(pixels)")
}

// MARK: app icon (macOS grid: 824 pt rounded square centered in a 1024 canvas)

let appSource = load("Resources/Icons/AppIcon-source.png")
let canvas = 1024
let inset: CGFloat = 100
let body = CGRect(x: inset, y: inset, width: CGFloat(canvas) - 2 * inset, height: CGFloat(canvas) - 2 * inset)
let master = context(canvas, canvas)
master.addPath(
    CGPath(roundedRect: body, cornerWidth: body.width * 0.2237, cornerHeight: body.width * 0.2237, transform: nil))
master.clip()
master.draw(appSource, in: body)
let masterImage = master.makeImage()!

let iconset = NSTemporaryDirectory() + "VirtualRemote-\(UUID().uuidString).iconset"
try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(atPath: iconset) }
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = base * scale
        let ctx = context(pixels, pixels)
        ctx.draw(masterImage, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        save(ctx.makeImage()!, to: iconset + "/" + name)
    }
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", "-o", path("Resources/AppIcon.icns"), iconset]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("AppIcon.icns written")
