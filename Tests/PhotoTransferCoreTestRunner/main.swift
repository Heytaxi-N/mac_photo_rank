import AppKit
import Foundation
import PhotoTransferCore

@main
struct PhotoTransferCoreTestRunner {
    static func main() throws {
        try selectionOrderAssignsAndCompactsNumbers()
        try fileNameUsesFolderNameAndPaddedSequence()
        try uniqueFolderAddsNumericSuffix()
        try exporterWritesOnlySelectedPhotosAsJPEGs()
        try overwriteRemovesStaleOutputFolder()
        print("PhotoTransferCoreTestRunner: all tests passed")
    }

    private static func selectionOrderAssignsAndCompactsNumbers() throws {
        let first = OrderedPhoto(id: UUID(), sourceURL: URL(fileURLWithPath: "/tmp/a.jpg"))
        let second = OrderedPhoto(id: UUID(), sourceURL: URL(fileURLWithPath: "/tmp/b.jpg"))
        let third = OrderedPhoto(id: UUID(), sourceURL: URL(fileURLWithPath: "/tmp/c.jpg"))

        var order = PhotoOrder()
        order.toggle(first.id)
        order.toggle(second.id)
        order.toggle(third.id)
        order.toggle(second.id)

        try expect(order.number(for: first.id) == 1, "first photo should keep number 1")
        try expect(order.number(for: second.id) == nil, "second photo should be unselected")
        try expect(order.number(for: third.id) == 2, "third photo should compact to number 2")
        try expect(order.orderedIDs == [first.id, third.id], "ordered IDs should compact after removal")
    }

    private static func fileNameUsesFolderNameAndPaddedSequence() throws {
        try expect(ExportNamer.fileName(folderName: "红标短裤", index: 1, totalCount: 10) == "红标短裤01.jpg", "index 1 should be padded")
        try expect(ExportNamer.fileName(folderName: "红标短裤", index: 10, totalCount: 10) == "红标短裤10.jpg", "index 10 should not gain extra padding")
        try expect(ExportNamer.fileName(folderName: "红标短裤", index: 100, totalCount: 120) == "红标短裤100.jpg", "three digit totals should use three digits")
    }

    private static func uniqueFolderAddsNumericSuffix() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("红标短裤"), withIntermediateDirectories: true)

        let resolved = try ExportDestination.resolveFolder(
            rootDirectory: root,
            folderName: "红标短裤",
            conflictResolution: .createUniqueFolder
        )

        try expect(resolved.lastPathComponent == "红标短裤-2", "existing folder should resolve to -2 suffix")
    }

    private static func exporterWritesOnlySelectedPhotosAsJPEGs() throws {
        let root = try makeTemporaryDirectory()
        let source = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: source)
        }

        let firstURL = source.appendingPathComponent("first.png")
        let secondURL = source.appendingPathComponent("second.png")
        let ignoredURL = source.appendingPathComponent("ignored.txt")
        try makePNGData(color: .red).write(to: firstURL)
        try makePNGData(color: .blue).write(to: secondURL)
        try "not an image".write(to: ignoredURL, atomically: true, encoding: .utf8)

        let first = OrderedPhoto(id: UUID(), sourceURL: firstURL)
        let second = OrderedPhoto(id: UUID(), sourceURL: secondURL)
        let ignored = OrderedPhoto(id: UUID(), sourceURL: ignoredURL)
        var order = PhotoOrder()
        order.toggle(second.id)
        order.toggle(first.id)

        let result = try PhotoExporter.export(
            photos: [first, second, ignored],
            order: order,
            folderName: "红标短裤",
            rootDirectory: root,
            conflictResolution: .cancelIfExists
        )

        try expect(result.exportedCount == 2, "two selected images should be exported")
        try expect(result.skippedCount == 1, "one unselected item should be skipped")
        try expect(result.outputDirectory.lastPathComponent == "红标短裤", "output folder should use folder name")
        try expect(FileManager.default.fileExists(atPath: result.outputDirectory.appendingPathComponent("红标短裤01.jpg").path), "first JPG should exist")
        try expect(FileManager.default.fileExists(atPath: result.outputDirectory.appendingPathComponent("红标短裤02.jpg").path), "second JPG should exist")
        try expect(!FileManager.default.fileExists(atPath: result.outputDirectory.appendingPathComponent("红标短裤03.jpg").path), "unselected file should not create third JPG")
    }

    private static func overwriteRemovesStaleOutputFolder() throws {
        let root = try makeTemporaryDirectory()
        let source = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: source)
        }

        let existingFolder = root.appendingPathComponent("红标短裤", isDirectory: true)
        try FileManager.default.createDirectory(at: existingFolder, withIntermediateDirectories: true)
        try "stale".write(to: existingFolder.appendingPathComponent("红标短裤03.jpg"), atomically: true, encoding: .utf8)

        let photoURL = source.appendingPathComponent("single.png")
        try makePNGData(color: .green).write(to: photoURL)
        let photo = OrderedPhoto(id: UUID(), sourceURL: photoURL)
        var order = PhotoOrder()
        order.toggle(photo.id)

        let result = try PhotoExporter.export(
            photos: [photo],
            order: order,
            folderName: "红标短裤",
            rootDirectory: root,
            conflictResolution: .overwrite
        )

        try expect(result.exportedCount == 1, "overwrite should export selected image")
        try expect(!FileManager.default.fileExists(atPath: existingFolder.appendingPathComponent("红标短裤03.jpg").path), "overwrite should remove stale files")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw TestFailure(message)
        }
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoTransferTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func makeImage(color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 12, height: 12))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: 12, height: 12).fill()
        image.unlockFocus()
        return image
    }

    private static func makePNGData(color: NSColor) throws -> Data {
        let image = makeImage(color: color)
        guard
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
            let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
        else {
            throw TestFailure("failed to create PNG data")
        }
        return data
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
