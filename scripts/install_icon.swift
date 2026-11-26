#!/usr/bin/env swift
import AppKit
import CoreGraphics

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: install_icon.swift <input.png>\n", stderr)
    exit(1)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
guard let sourceImage = NSImage(contentsOf: inputURL),
      let sourceCG = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("Failed to load image at \(inputURL.path)\n", stderr)
    exit(1)
}

let rootDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconDir = rootDir.appendingPathComponent("Lepora/Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

/// Apple-style continuous superellipse (squircle) path for authentic macOS icons
func continuousSquirclePath(in rect: CGRect, radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let x = rect.minX
    let y = rect.minY
    let w = rect.width
    let h = rect.height
    let r = min(radius, min(w, h) / 2)
    // Superellipse control factor (~0.12 extra smoothness over circular arc)
    let k = r * 0.44

    path.move(to: CGPoint(x: x + r, y: y))
    path.addLine(to: CGPoint(x: x + w - r, y: y))
    path.addCurve(to: CGPoint(x: x + w, y: y + r),
                  control1: CGPoint(x: x + w - k, y: y),
                  control2: CGPoint(x: x + w, y: y + k))
    path.addLine(to: CGPoint(x: x + w, y: y + h - r))
    path.addCurve(to: CGPoint(x: x + w - r, y: y + h),
                  control1: CGPoint(x: x + w, y: y + h - k),
                  control2: CGPoint(x: x + w - k, y: y + h))
    path.addLine(to: CGPoint(x: x + r, y: y + h))
    path.addCurve(to: CGPoint(x: x, y: y + h - r),
                  control1: CGPoint(x: x + k, y: y + h),
                  control2: CGPoint(x: x, y: y + h - k))
    path.addLine(to: CGPoint(x: x, y: y + r))
    path.addCurve(to: CGPoint(x: x + r, y: y),
                  control1: CGPoint(x: x, y: y + k),
                  control2: CGPoint(x: x + k, y: y))
    path.closeSubpath()
    return path
}

func renderIcon(px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    cg.setAllowsAntialiasing(true)
    cg.setShouldAntialias(true)
    cg.interpolationQuality = .high

    // Standard macOS Big Sur–27 app icon grid (~82.4% body inside 1024 canvas)
    let inset = s * 0.088
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.225
    let squircle = continuousSquirclePath(in: rect, radius: radius)

    // Airy macOS icon drop shadow
    cg.saveGState()
    cg.setShadow(
        offset: CGSize(width: 0, height: -s * 0.015),
        blur: s * 0.034,
        color: NSColor.black.withAlphaComponent(0.20).cgColor
    )
    cg.addPath(squircle)
    cg.setFillColor(NSColor.black.cgColor)
    cg.fillPath()
    cg.restoreGState()

    // Clip artwork into squircle
    cg.saveGState()
    cg.addPath(squircle)
    cg.clip()

    // Center-crop source to square and draw crisply
    let srcW = CGFloat(sourceCG.width)
    let srcH = CGFloat(sourceCG.height)
    let side = min(srcW, srcH)
    let cropRect = CGRect(x: (srcW - side) / 2, y: (srcH - side) / 2, width: side, height: side)
    let cropped = sourceCG.cropping(to: cropRect) ?? sourceCG
    cg.draw(cropped, in: rect)

    // Delicate Liquid Glass top specular inner bevel rim
    let cs = CGColorSpaceCreateDeviceRGB()
    let rimGrad = CGGradient(
        colorsSpace: cs,
        colors: [
            NSColor.white.withAlphaComponent(0.58).cgColor,
            NSColor.white.withAlphaComponent(0.14).cgColor,
            NSColor.white.withAlphaComponent(0.03).cgColor,
            NSColor.white.withAlphaComponent(0.24).cgColor,
        ] as CFArray,
        locations: [0.0, 0.35, 0.72, 1.0]
    )!
    cg.saveGState()
    cg.addPath(squircle)
    cg.setLineWidth(max(1.0, s * 0.016))
    cg.replacePathWithStrokedPath()
    cg.clip()
    cg.drawLinearGradient(
        rimGrad,
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.maxX, y: rect.minY),
        options: []
    )
    cg.restoreGState()
    cg.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in sizes {
    let data = renderIcon(px: px)
    try data.write(to: iconDir.appendingPathComponent(name))
}
print("Installed all \(sizes.count) AppIcon assets from \(inputURL.lastPathComponent)")
