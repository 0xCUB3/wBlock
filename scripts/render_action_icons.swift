#!/usr/bin/env swift

import AppKit

// Run from the repository root: swift scripts/render_action_icons.swift
// Draws the toolbar icon as the wBlock "w" mark, parsed at runtime from the app
// icon's layer SVG so the toolbar and app icon share one shape. Mac Safari crops
// a toolbar icon to its opaque bounds and scales that square to 19pt, so the
// w is fitted to the square with its opaque bounds touching the top and bottom
// (or sides, whichever limits) and centered. Safari tints toolbar icons using
// their alpha mask, so gray alone cannot distinguish disabled protection; the
// disabled variant cuts a gap around a diagonal slash instead.
let directory = URL(fileURLWithPath: "wBlock Scripts (iOS)/Resources/assets/images", isDirectory: true)
let source = URL(fileURLWithPath: "wBlock/Resources/App Icons/AppIcon.icon/Assets/2 - Layer 2.svg")
let gray = CGColor(gray: 0.56, alpha: 1)

func write(_ context: CGContext, _ name: String) throws {
    guard let output = context.makeImage(),
          let png = NSBitmapImageRep(cgImage: output).representation(using: .png, properties: [:]) else {
        fatalError("Cannot encode \(name)")
    }
    try png.write(to: directory.appendingPathComponent(name))
}

// Reads the w path's d attribute and builds it. Supports the absolute M, L, C,
// and Z commands the layer uses; the SVG's translate(128, 77) is applied here.
func loadW() throws -> CGPath {
    let svg = try String(contentsOf: source, encoding: .utf8)
    let d = svg.components(separatedBy: " d=\"")[1].components(separatedBy: "\"")[0]
    var tokens: [String] = []
    var current = ""
    func flush() {
        if !current.isEmpty { tokens.append(current); current = "" }
    }
    for character in d {
        if character.isLetter {
            flush()
            tokens.append(String(character))
        } else if character == " " || character == "," {
            flush()
        } else if character == "-" && !current.isEmpty {
            flush()
            current = "-"
        } else {
            current.append(character)
        }
    }
    flush()

    let path = CGMutablePath()
    var i = 0
    var command = ""
    func number() -> CGFloat { defer { i += 1 }; return CGFloat(Double(tokens[i])!) }
    func point() -> CGPoint { let x = number() + 128; return CGPoint(x: x, y: number() + 77) }
    while i < tokens.count {
        if tokens[i].first!.isLetter { command = tokens[i]; i += 1 }
        switch command {
        case "M": path.move(to: point()); command = "L"
        case "L": path.addLine(to: point())
        case "C":
            let control1 = point(), control2 = point()
            path.addCurve(to: point(), control1: control1, control2: control2)
        case "Z": path.closeSubpath(); command = ""
        default: fatalError("Unsupported path command \(command) in \(source.lastPathComponent)")
        }
    }
    return path
}

let w = try loadW()
let opaque = w.boundingBoxOfPath

for size in [16, 19, 32, 38, 48, 96, 128, 256, 512] {
    guard let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8,
        bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("Cannot render icon at \(size)px") }

    // Scale the w uniformly to fit the square, then flip from the SVG's
    // top-left origin to the context's bottom-left origin.
    let side = CGFloat(size)
    let scale = min(side / opaque.width, side / opaque.height)
    let offsetX = (side - opaque.width * scale) / 2
    let offsetY = (side - opaque.height * scale) / 2
    context.saveGState()
    context.concatenate(CGAffineTransform(
        a: scale, b: 0, c: 0, d: -scale,
        tx: offsetX - opaque.minX * scale, ty: offsetY + opaque.maxY * scale
    ))
    context.addPath(w)
    context.setFillColor(CGColor(gray: 0, alpha: 0.85))
    context.fillPath()
    context.restoreGState()
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
