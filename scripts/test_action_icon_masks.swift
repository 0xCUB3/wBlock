import AppKit
let directory = URL(fileURLWithPath: "wBlock Scripts (iOS)/Resources/assets/images")
for size in [48, 96, 128, 256, 512] {
    func pixels(_ disabled: Bool) throws -> [UInt8] {
        let url = directory.appendingPathComponent("icon-\(disabled ? "disabled-" : "")\(size).png")
        let image = NSBitmapImageRep(data: try Data(contentsOf: url))!.cgImage!
        precondition(image.width == size && image.height == size)
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        return Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self), count: size * size * 4))
    }
    let enabled = try pixels(false), disabled = try pixels(true)
    let changed = stride(from: 3, to: enabled.count, by: 4).filter { abs(Int(enabled[$0]) - Int(disabled[$0])) > 128 }.count
    precondition(changed > size * size / 25, "Shape must survive template tinting")
    precondition(disabled[3] == 0, "Transparent background required")
    let center = ((size / 2) * size + size / 2) * 4 + 3
    precondition(disabled[center] > 200 && enabled[center] < 20, "Slash must cross the empty shield center")
    print("PASS: \(size)px, \(changed) distinctly changed alpha pixels, slash and transparency intact")
}
