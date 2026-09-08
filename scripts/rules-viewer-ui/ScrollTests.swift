import XCTest
import UIKit

final class ScrollTests: XCTestCase {
    @MainActor
    private func position(_ app: XCUIApplication) -> (x: Int, y: Int) {
        let fields = app.staticTexts["geometry"].label.split(separator: " ")
        return (Int(fields[0].dropFirst(2)) ?? -1, Int(fields[1].dropFirst(2)) ?? -1)
    }

    @MainActor
    private func assertRenderedText(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let image = screenshot.image.cgImage else { XCTFail("No rendered image"); return }
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let coloredPixels = pixels.withUnsafeMutableBytes { bytes -> Int in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            var count = 0
            // Exclude controls: only colored glyphs in the document should count.
            for y in (height / 4)..<(height * 3 / 4) {
                for x in 0..<width {
                    let i = (y * width + x) * 4
                    let r = Int(bytes[i]), g = Int(bytes[i + 1]), b = Int(bytes[i + 2])
                    if max(r, g, b) - min(r, g, b) > 80 { count += 1 }
                }
            }
            return count
        }
        XCTAssertGreaterThan(coloredPixels, 1000, "The scrolled viewport must contain colored text, not blank space")
    }

    @MainActor
    func testPanKeepsTextAndOffset() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 20))
        sleep(3)
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        sleep(3)
        let x = position(app).x
        XCTAssertGreaterThan(x, 100)
        assertRenderedText("Horizontal pan")
        sleep(3)
        XCTAssertEqual(position(app).x, x, "Highlighting must not snap the viewport back")

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
        sleep(3)
        XCTAssertEqual(position(app).x, x)
        XCTAssertGreaterThan(position(app).y, 100)
        assertRenderedText("Vertical pan at horizontal offset")

        let toggle = app.switches["Wrap"].coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        toggle.tap()
        sleep(3)
        XCTAssertEqual(position(app).x, 0)
        toggle.tap()
        sleep(3)
        start.press(forDuration: 0.05, thenDragTo: end)
        sleep(3)
        XCTAssertGreaterThan(position(app).x, 100)
        assertRenderedText("Wrapping disabled again")

        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(3)
        XCTAssertGreaterThan(position(app).x, 100)
        assertRenderedText("Landscape")
    }
}
