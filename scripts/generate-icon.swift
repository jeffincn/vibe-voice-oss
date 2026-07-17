#!/usr/bin/env swift
import AppKit
import Foundation

let outputURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/VibeVoice.icns")
let fileManager = FileManager.default
let iconsetURL = fileManager.temporaryDirectory
    .appendingPathComponent("VibeVoice-\(UUID().uuidString).iconset")
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
defer { try? fileManager.removeItem(at: iconsetURL) }

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

for (filename, pixels) in variants {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { fatalError("Cannot create \(pixels)px bitmap") }
    bitmap.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()

    let inset = CGFloat(pixels) * 0.07
    let tile = NSRect(x: inset, y: inset, width: CGFloat(pixels) - inset * 2, height: CGFloat(pixels) - inset * 2)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: CGFloat(pixels) * 0.22, yRadius: CGFloat(pixels) * 0.22)

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = CGFloat(pixels) * 0.045
    shadow.shadowOffset = NSSize(width: 0, height: -CGFloat(pixels) * 0.018)
    shadow.set()
    NSColor(calibratedRed: 0.035, green: 0.038, blue: 0.042, alpha: 1).setFill()
    tilePath.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    let symbolConfiguration = NSImage.SymbolConfiguration(
        pointSize: CGFloat(pixels) * 0.42,
        weight: .medium
    ).applying(NSImage.SymbolConfiguration(paletteColors: [
        NSColor(calibratedRed: 0.96, green: 0.96, blue: 0.93, alpha: 1)
    ]))

    if let symbol = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Vibe Voice")?
        .withSymbolConfiguration(symbolConfiguration) {
        let side = CGFloat(pixels) * 0.52
        let symbolRect = NSRect(
            x: (CGFloat(pixels) - side) / 2,
            y: (CGFloat(pixels) - side) / 2,
            width: side,
            height: side
        )
        symbol.draw(in: symbolRect)
    }

    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Cannot encode \(pixels)px icon")
    }
    try png.write(to: iconsetURL.appendingPathComponent(filename))
}

try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("iconutil failed") }
print(outputURL.path)
