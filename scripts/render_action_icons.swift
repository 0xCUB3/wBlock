#!/usr/bin/env swift

import AppKit

// Run from the repository root: swift scripts/render_action_icons.swift
// Draws the toolbar shield from vector geometry at every size. Mac Safari crops
// a toolbar icon to its opaque bounds and scales that square to 19pt, so the
// shield spans the full height and its sides sit on pixel boundaries. Safari tints toolbar icons using their alpha mask, so
// gray alone cannot distinguish disabled protection; the disabled variant cuts
// a gap around a diagonal slash instead.
let directory = URL(fileURLWithPath: "wBlock Scripts (iOS)/Resources/assets/images", isDirectory: true)
let gray = CGColor(gray: 0.56, alpha: 1)

func write(_ context: CGContext, _ name: String) throws {
    guard let output = context.makeImage(),
          let png = NSBitmapImageRep(cgImage: output).representation(using: .png, properties: [:]) else {
        fatalError("Cannot encode \(name)")
    }
    try png.write(to: directory.appendingPathComponent(name))
}

for size in [16, 19, 32, 38, 48, 96, 128, 256, 512] {
    guard let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8,
        bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("Cannot render icon at \(size)px") }

    // Shield outline in a 512-unit, top-left-origin design space, mapped so
    // the stroke's outer edge touches the top and bottom rows.
    let side = CGFloat(size)
    let stroke = max(1, (side * 38 / 512).rounded())
    let half = stroke / 2
    let left = (side * 74 / 512 - half).rounded() + half
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: left + (x - 74) * (side - 2 * left) / 377,
                y: side - half - (y - 32) * (side - stroke) / 446)
    }
    let shield = CGMutablePath()
    shield.move(to: point(262.5, 32))
    shield.addLine(to: point(451, 104))
    shield.addLine(to: point(451, 318))
    shield.addQuadCurve(to: point(262.5, 478), control: point(440, 390))
    shield.addQuadCurve(to: point(74, 318), control: point(85, 390))
    shield.addLine(to: point(74, 104))
    shield.closeSubpath()
    context.addPath(shield)
    context.setLineWidth(stroke)
    context.setLineJoin(.round)
    context.setStrokeColor(CGColor(gray: 0, alpha: 0.85))
    context.strokePath()
    try write(context, "icon-\(size).png")

    let bounds = CGRect(x: 0, y: 0, width: side, height: side)
    context.setBlendMode(.sourceIn)
    context.setFillColor(gray)
    context.fill(bounds)

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
    try write(context, "icon-disabled-\(size).png")
}
