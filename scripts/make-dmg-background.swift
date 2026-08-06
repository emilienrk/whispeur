#!/usr/bin/env swift
//
// Draws the DMG window background: an arrow pointing from the app to the
// Applications alias. Run it only to regenerate scripts/assets/dmg-background@2x.png
// — the build consumes the committed image, not this script.
//
// Usage: swift scripts/make-dmg-background.swift <output.png> <scale>

import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3,
      let scale = Double(arguments[2]) else {
    FileHandle.standardError.write(Data("usage: make-dmg-background.swift <output.png> <scale>\n".utf8))
    exit(1)
}

let outputPath = arguments[1]

// Must match the window and icon positions in scripts/make-dmg.sh.
let windowWidth = 600.0
let windowHeight = 400.0
let iconCenterFromTop = 170.0

let pixelWidth = Int(windowWidth * scale)
let pixelHeight = Int(windowHeight * scale)

guard let context = CGContext(
    data: nil,
    width: pixelWidth,
    height: pixelHeight,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write(Data("failed to create the drawing context\n".utf8))
    exit(1)
}

context.scaleBy(x: scale, y: scale)

// Flat off-white: the Finder draws icon labels in dark grey over this.
context.setFillColor(CGColor(red: 0.976, green: 0.976, blue: 0.980, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: windowWidth, height: windowHeight))

// CoreGraphics has its origin at the bottom left, the Finder at the top left.
let arrowY = windowHeight - iconCenterFromTop
let arrowStart = 262.0
let arrowEnd = 338.0
let headLength = 16.0
let headHalfWidth = 9.0

context.setStrokeColor(CGColor(red: 0.62, green: 0.62, blue: 0.65, alpha: 1))
context.setLineWidth(3)
context.setLineCap(.round)
context.move(to: CGPoint(x: arrowStart, y: arrowY))
context.addLine(to: CGPoint(x: arrowEnd - headLength + 2, y: arrowY))
context.strokePath()

context.setFillColor(CGColor(red: 0.62, green: 0.62, blue: 0.65, alpha: 1))
context.move(to: CGPoint(x: arrowEnd, y: arrowY))
context.addLine(to: CGPoint(x: arrowEnd - headLength, y: arrowY + headHalfWidth))
context.addLine(to: CGPoint(x: arrowEnd - headLength, y: arrowY - headHalfWidth))
context.closePath()
context.fillPath()

guard let image = context.makeImage() else {
    FileHandle.standardError.write(Data("failed to render the image\n".utf8))
    exit(1)
}

let bitmap = NSBitmapImageRep(cgImage: image)
guard let data = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("failed to encode the PNG\n".utf8))
    exit(1)
}

do {
    try data.write(to: URL(fileURLWithPath: outputPath))
} catch {
    FileHandle.standardError.write(Data("failed to write \(outputPath): \(error)\n".utf8))
    exit(1)
}
