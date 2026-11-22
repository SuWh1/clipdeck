import AppKit
import Testing
@testable import ClipdeckCore

private func makePasteboard() -> NSPasteboard {
    NSPasteboard(name: NSPasteboard.Name("clipdeck-test-\(UUID().uuidString)"))
}

@Suite("PasteboardSnapshot")
struct PasteboardSnapshotTests {
    @Test("should read text, rich text and types in order")
    func text() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("hello", forType: .string)
        pasteboard.setData(Data("{\\rtf1 hello}".utf8), forType: .rtf)
        let snapshot = PasteboardSnapshot(reading: pasteboard)
        #expect(snapshot.string == "hello")
        #expect(snapshot.rtf == Data("{\\rtf1 hello}".utf8))
        #expect(snapshot.types.first == NSPasteboard.PasteboardType.string.rawValue)
        #expect(snapshot.fileURLs.isEmpty)
        #expect(snapshot.imageData == nil)
    }

    @Test("should read image data")
    func image() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setData(TestImages.png(), forType: .png)
        #expect(PasteboardSnapshot(reading: pasteboard).imageData == TestImages.png())
    }

    @Test("should not read image data when text comes first")
    func skipsImageBehindText() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("cells", forType: .string)
        pasteboard.setData(TestImages.png(), forType: .png)
        #expect(PasteboardSnapshot(reading: pasteboard).imageData == nil)
    }

    @Test("should read copied files")
    func files() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.writeObjects([URL(fileURLWithPath: "/tmp/a.txt") as NSURL])
        #expect(PasteboardSnapshot(reading: pasteboard).fileURLs.map(\.path) == ["/tmp/a.txt"])
    }

    @Test("should read secret markers so the classifier can skip them")
    func concealed() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("pw", forType: .string)
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        let snapshot = PasteboardSnapshot(reading: pasteboard)
        #expect(ClipClassifier(ignoredBundleIDs: []).classify(snapshot, source: nil) == nil)
    }
}

@Suite("PasteboardWriter")
struct PasteboardWriterTests {
    private let classifier = ClipClassifier(ignoredBundleIDs: [])

    private func roundTrip(_ candidate: ClipCandidate, plainTextOnly: Bool = false) throws -> (NSPasteboard, ClipCandidate?) {
        let store = try makeStore()
        let item = try store.record(candidate)
        let pasteboard = makePasteboard()
        let imageData = try store.imageURL(for: item).map { try Data(contentsOf: $0) }
        PasteboardWriter.write(item, imageData: imageData, plainTextOnly: plainTextOnly, to: pasteboard)
        return (pasteboard, classifier.classify(PasteboardSnapshot(reading: pasteboard), source: nil))
    }

    @Test("should write text with its rich text")
    func richText() throws {
        let rtf = Data("{\\rtf1 hi}".utf8)
        let (pasteboard, reread) = try roundTrip(ClipCandidate(kind: .text, text: "hi", rtf: rtf))
        #expect(pasteboard.data(forType: .rtf) == rtf)
        #expect(reread?.contentHash == textCandidate("hi").contentHash)
    }

    @Test("should write only plain text when asked")
    func plain() throws {
        let (pasteboard, _) = try roundTrip(ClipCandidate(kind: .text, text: "hi", rtf: Data("{\\rtf1 hi}".utf8)), plainTextOnly: true)
        #expect(pasteboard.string(forType: .string) == "hi")
        #expect(pasteboard.data(forType: .rtf) == nil)
    }

    @Test("should write links as text and as a web address")
    func link() throws {
        let candidate = ClipCandidate(kind: .link, text: "https://example.com")
        let (pasteboard, reread) = try roundTrip(candidate)
        #expect(pasteboard.string(forType: .URL) == "https://example.com")
        #expect(reread?.contentHash == candidate.contentHash)
    }

    @Test("should write images as png and tiff")
    func image() throws {
        let candidate = imageCandidate()
        let (pasteboard, reread) = try roundTrip(candidate)
        #expect(pasteboard.data(forType: .png) == candidate.image?.png)
        #expect(pasteboard.data(forType: .tiff) != nil)
        #expect(reread?.contentHash == candidate.contentHash)
    }

    @Test("should write files as file references")
    func files() throws {
        let candidate = ClipCandidate(kind: .file, text: "/tmp/a.txt\n/tmp/b.txt")
        let (pasteboard, reread) = try roundTrip(candidate)
        #expect(PasteboardSnapshot(reading: pasteboard).fileURLs.map(\.path) == ["/tmp/a.txt", "/tmp/b.txt"])
        #expect(reread?.contentHash == candidate.contentHash)
    }

    @Test("should refuse to write an image whose file is missing")
    func missingImage() throws {
        let store = try makeStore()
        let item = try store.record(imageCandidate())
        let pasteboard = makePasteboard()
        let written = PasteboardWriter.write(item, imageData: nil, plainTextOnly: false, to: pasteboard)
        #expect(!written)
    }
}
