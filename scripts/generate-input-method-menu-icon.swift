#!/usr/bin/env swift
import AppKit
import Foundation

/// Builds the input-source menu PDF from `Resources/VibeTypeIcon.png`.
///
/// Menu / Text Input icons are effectively template images: opaque pixels become
/// the system tint. A full-bleed black square therefore collapses into a solid
/// black blob. Extract the light glyph, paint it black on a transparent canvas.
let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let sourceURL = root.appendingPathComponent("Resources/VibeTypeIcon.png")
let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first
    ?? root.appendingPathComponent("Resources/VibeTypeMenu.pdf").path)

guard let source = NSImage(contentsOf: sourceURL),
      let cgSource = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("error: missing icon source at \(sourceURL.path)\n", stderr)
    exit(1)
}

let pixelSize = 256
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixelSize,
    pixelsHigh: pixelSize,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("error: cannot allocate bitmap\n", stderr)
    exit(1)
}
bitmap.size = NSSize(width: pixelSize, height: pixelSize)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize).fill()

// Draw the brand mark, then rewrite pixels: keep light strokes as opaque black.
let srcRep = NSBitmapImageRep(cgImage: cgSource)
srcRep.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.bitmapData else {
    fputs("error: no bitmap data\n", stderr)
    exit(1)
}
let rowBytes = bitmap.bytesPerRow
let threshold: UInt8 = 140
for y in 0..<pixelSize {
    let row = data.advanced(by: y * rowBytes)
    for x in 0..<pixelSize {
        let p = row.advanced(by: x * 4)
        let r = p[0], g = p[1], b = p[2]
        let luma = (Int(r) * 299 + Int(g) * 587 + Int(b) * 114) / 1000
        if luma >= Int(threshold) {
            // Glyph → opaque black (system tints this).
            p[0] = 0; p[1] = 0; p[2] = 0; p[3] = 255
        } else {
            // Background → fully transparent.
            p[0] = 0; p[1] = 0; p[2] = 0; p[3] = 0
        }
    }
}

guard let glyph = bitmap.cgImage else {
    fputs("error: cannot make CGImage from template bitmap\n", stderr)
    exit(1)
}

// 18pt matches typical input-source menu glyph size; PDF keeps it sharp @2x/@3x.
let pointSize = CGSize(width: 18, height: 18)
var mediaBox = CGRect(origin: .zero, size: pointSize)
guard let consumer = CGDataConsumer(url: output as CFURL),
      let pdf = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
    fputs("error: cannot create PDF at \(output.path)\n", stderr)
    exit(1)
}

pdf.beginPDFPage(nil)
pdf.clear(mediaBox)
// Slight inset so the mark doesn't clip against neighboring menu chrome.
let inset: CGFloat = 1.5
pdf.draw(glyph, in: mediaBox.insetBy(dx: inset, dy: inset))
pdf.endPDFPage()
pdf.closePDF()
print(output.path)
