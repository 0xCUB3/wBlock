#!/usr/bin/env swift

import AppKit

// Run from the repository root: swift scripts/render_disabled_action_icons.swift
// Safari tints toolbar icons using their alpha mask, so gray alone cannot
// distinguish disabled protection. Cut a gap around a diagonal slash instead.
let directory = URL(fileURLWithPath: "wBlock Scripts (iOS)/Resources/assets/images", isDirectory: true)
let gray = CGColor(gray: 0.56, alpha: 1)

for size in [48, 96, 128, 256, 512] {
    let source = directory.appendingPathComponent("icon-\(size).png")
    guard let image = NSBitmapImageRep(data: try Data(contentsOf: source))?.cgImage,
          image.width == size, image.height == size,
          let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else {
        fatalError("Cannot render icon at \(size)px")
    }

    let side = CGFloat(size)
    let bounds = CGRect(x: 0, y: 0, width: side, height: side)
    context.clip(to: bounds, mask: image)
    context.setFillColor(gray)
    context.fill(bounds)
    context.resetClip()

    func strokeSlash(width: CGFloat, blendMode: CGBlendMode) {
        context.setBlendMode(blendMode)
        context.setStrokeColor(gray)
        context.setLineWidth(side * width)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: side * 0.18, y: side * 0.82))
        context.addLine(to: CGPoint(x: side * 0.82, y: side * 0.18))
        context.strokePath()
    }

    strokeSlash(width: 0.19, blendMode: .clear)
    strokeSlash(width: 0.075, blendMode: .normal)

    guard let output = context.makeImage(),
          let png = NSBitmapImageRep(cgImage: output).representation(using: .png, properties: [:]) else {
        fatalError("Cannot encode icon at \(size)px")
    }
    try png.write(to: directory.appendingPathComponent("icon-disabled-\(size).png"))
}
