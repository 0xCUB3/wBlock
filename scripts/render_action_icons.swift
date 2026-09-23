#!/usr/bin/env swift

import AppKit

// Run from the repository root: swift scripts/render_action_icons.swift
// Draws the toolbar shield from vector geometry at every size so Retina
// toolbars stay sharp. Safari tints toolbar icons using their alpha mask, so
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

for size in [48, 96, 128, 256, 512] {
    guard let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8,
        bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("Cannot render icon at \(size)px") }

    // Shield outline in a 512-unit, top-left-origin design space.
    let side = CGFloat(size)
    let shield = CGMutablePath()
    shield.move(to: CGPoint(x: 262, y: 32))
    shield.addLine(to: CGPoint(x: 451, y: 104))
    shield.addLine(to: CGPoint(x: 451, y: 318))
    shield.addQuadCurve(to: CGPoint(x: 262, y: 478), control: CGPoint(x: 440, y: 390))
    shield.addQuadCurve(to: CGPoint(x: 74, y: 318), control: CGPoint(x: 84, y: 390))
    shield.addLine(to: CGPoint(x: 74, y: 104))
    shield.closeSubpath()
    var transform = CGAffineTransform(a: side / 512, b: 0, c: 0, d: -side / 512, tx: 0, ty: side)
    context.addPath(shield.copy(using: &transform)!)
    context.setLineWidth(side * 38 / 512)
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
