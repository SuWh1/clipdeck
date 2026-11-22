import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import ClipdeckCore

enum TestImages {
    static func image(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        for x in 0..<width {
            context.setFillColor(red: CGFloat(x) / CGFloat(width), green: 0.5, blue: 0.2, alpha: 1)
            context.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }
        return context.makeImage()!
    }

    static func encode(_ image: CGImage, as type: UTType) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    static func png(width: Int = 4, height: Int = 3) -> Data {
        encode(image(width: width, height: height), as: .png)
    }

    static func tiff(width: Int = 4, height: Int = 3) -> Data {
        encode(image(width: width, height: height), as: .tiff)
    }
}

func makeTempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("clipdeck-tests-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

final class TestClock: @unchecked Sendable {
    private(set) var now: Date

    init(_ start: Date = Date(timeIntervalSinceReferenceDate: 800_000_000)) {
        now = start
    }

    func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}

let notesSource = ClipSource(bundleID: "com.apple.Notes", name: "Notes")

func textCandidate(_ text: String, source: ClipSource? = notesSource) -> ClipCandidate {
    ClipCandidate(kind: .text, text: text, source: source)
}

func imageCandidate(width: Int = 4, height: Int = 3) -> ClipCandidate {
    ClipCandidate(
        kind: .image, text: "",
        image: ImagePayload(png: TestImages.png(width: width, height: height), width: width, height: height),
        source: ClipSource(bundleID: "com.apple.Preview", name: "Preview")
    )
}

func makeStore(clock: TestClock = TestClock(), directory: URL = makeTempDirectory()) throws -> HistoryStore {
    try HistoryStore(directory: directory, now: { clock.now })
}
