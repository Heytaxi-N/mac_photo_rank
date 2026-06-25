import AppKit
import AVFoundation
import Foundation
import PhotoTransferCore

@main
struct PhotoTransferCoreTestRunner {
    static func main() throws {
        try selectionOrderAssignsAndCompactsNumbers()
        try fileNameUsesFolderNameAndPaddedSequence()
        try fileNameUsesNumberedNameByDefault()
        try fileNameUsesSizeChartNameWhenSelected()
        try detectsImageAndVideoFiles()
        try videoFileNameUsesIndependentSequence()
        try defaultRootDirectoryUsesWeidianProductsFolder()
        try uniqueFolderAddsNumericSuffix()
        try exporterWritesOnlySelectedPhotosAsJPEGs()
        try exporterNamesLastSelectedPhotoAsSizeChartWhenSelected()
        try exporterWritesImagesAndVideosWithSeparateSequences()
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
        try expect(ExportNamer.fileName(folderName: "红标短裤", index: 10, totalCount: 11) == "红标短裤10.jpg", "index 10 should not gain extra padding")
        try expect(ExportNamer.fileName(folderName: "红标短裤", index: 100, totalCount: 120) == "红标短裤100.jpg", "three digit totals should use three digits")
    }

    private static func fileNameUsesNumberedNameByDefault() throws {
        try expect(ExportNamer.fileName(folderName: "红标短裤", index: 3, totalCount: 3) == "红标短裤03.jpg", "last exported file should use numbered name by default")
    }

    private static func fileNameUsesSizeChartNameWhenSelected() throws {
        try expect(ExportNamer.fileName(folderName: "红标短裤", index: 3, totalCount: 3, hasSizeChart: true) == "尺码表.jpg", "last exported file should be named 尺码表.jpg when selected")
        try expect(ExportNamer.fileName(folderName: "红标短裤", index: 2, totalCount: 3, hasSizeChart: true) == "红标短裤02.jpg", "non-last exported file should keep numbered name")
    }

    private static func detectsImageAndVideoFiles() throws {
        try expect(MediaFileDetector.kind(for: URL(fileURLWithPath: "/tmp/a.png")) == .image, "png should be detected as image")
        try expect(MediaFileDetector.kind(for: URL(fileURLWithPath: "/tmp/a.mp4")) == .video, "mp4 should be detected as video")
        try expect(MediaFileDetector.kind(for: URL(fileURLWithPath: "/tmp/a.mkv")) == .video, "mkv should be detected as video by fallback")
        try expect(MediaFileDetector.kind(for: URL(fileURLWithPath: "/tmp/a.txt")) == nil, "txt should not be detected as media")
    }

    private static func videoFileNameUsesIndependentSequence() throws {
        try expect(ExportNamer.videoFileName(index: 1, totalCount: 12, pathExtension: "mp4") == "视频01.mp4", "first video should be padded")
        try expect(ExportNamer.videoFileName(index: 2, totalCount: 12, pathExtension: "mp4") == "视频02.mp4", "second video should use its own sequence")
        try expect(ExportNamer.videoFileName(index: 1, totalCount: 1, pathExtension: "") == "视频01", "extensionless video should not add a dot")
    }

    private static func defaultRootDirectoryUsesWeidianProductsFolder() throws {
        try expect(
            PhotoExporter.defaultRootDirectory.path == "/Users/nick/Downloads/weidian_products-main/商品图",
            "default root directory should point to weidian_products-main 商品图"
        )
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
        try expect(!FileManager.default.fileExists(atPath: result.outputDirectory.appendingPathComponent("尺码表.jpg").path), "size chart should not be exported unless selected")
        try expect(!FileManager.default.fileExists(atPath: result.outputDirectory.appendingPathComponent("红标短裤03.jpg").path), "unselected file should not create third JPG")
    }

    private static func exporterNamesLastSelectedPhotoAsSizeChartWhenSelected() throws {
        let root = try makeTemporaryDirectory()
        let source = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: source)
        }

        let firstURL = source.appendingPathComponent("first.png")
        let secondURL = source.appendingPathComponent("second.png")
        try makePNGData(color: .red).write(to: firstURL)
        try makePNGData(color: .blue).write(to: secondURL)

        let first = OrderedPhoto(id: UUID(), sourceURL: firstURL)
        let second = OrderedPhoto(id: UUID(), sourceURL: secondURL)
        var order = PhotoOrder()
        order.toggle(first.id)
        order.toggle(second.id)

        let result = try PhotoExporter.export(
            photos: [first, second],
            order: order,
            folderName: "红标短裤",
            rootDirectory: root,
            hasSizeChart: true,
            conflictResolution: .cancelIfExists
        )

        try expect(result.exportedCount == 2, "two selected images should be exported")
        try expect(FileManager.default.fileExists(atPath: result.outputDirectory.appendingPathComponent("红标短裤01.jpg").path), "first JPG should exist")
        try expect(FileManager.default.fileExists(atPath: result.outputDirectory.appendingPathComponent("尺码表.jpg").path), "last JPG should be named 尺码表")
        try expect(!FileManager.default.fileExists(atPath: result.outputDirectory.appendingPathComponent("红标短裤02.jpg").path), "last JPG should not use numbered name when size chart is selected")
    }

    private static func exporterWritesImagesAndVideosWithSeparateSequences() throws {
        let root = try makeTemporaryDirectory()
        let source = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: source)
        }

        let firstImageURL = source.appendingPathComponent("first.png")
        let secondImageURL = source.appendingPathComponent("second.png")
        let firstVideoURL = source.appendingPathComponent("first.mp4")
        let secondVideoURL = source.appendingPathComponent("second.mov")
        try makePNGData(color: .red).write(to: firstImageURL)
        try makePNGData(color: .blue).write(to: secondImageURL)
        try makeVideoFile(at: firstVideoURL, fileType: .mp4)
        try makeVideoFile(at: secondVideoURL, fileType: .mov)

        let firstVideo = OrderedPhoto(id: UUID(), sourceURL: firstVideoURL, kind: .video)
        let firstImage = OrderedPhoto(id: UUID(), sourceURL: firstImageURL)
        let secondVideo = OrderedPhoto(id: UUID(), sourceURL: secondVideoURL, kind: .video)
        let secondImage = OrderedPhoto(id: UUID(), sourceURL: secondImageURL)
        var order = PhotoOrder()
        order.toggle(firstVideo.id)
        order.toggle(firstImage.id)
        order.toggle(secondVideo.id)
        order.toggle(secondImage.id)

        let result = try PhotoExporter.export(
            photos: [firstImage, secondImage, firstVideo, secondVideo],
            order: order,
            folderName: "红标短裤",
            rootDirectory: root,
            hasSizeChart: true,
            conflictResolution: .cancelIfExists
        )

        try expect(result.exportedCount == 4, "all selected media should be exported")
        try expect(FileManager.default.fileExists(atPath: result.outputDirectory.appendingPathComponent("红标短裤01.jpg").path), "first selected image should use image sequence")
        try expect(FileManager.default.fileExists(atPath: result.outputDirectory.appendingPathComponent("尺码表.jpg").path), "last selected image should be size chart")
        try expect(!FileManager.default.fileExists(atPath: result.outputDirectory.appendingPathComponent("红标短裤02.jpg").path), "size chart should replace last image number")
        try expect(FileManager.default.fileExists(atPath: result.outputDirectory.appendingPathComponent("视频01.mp4").path), "first video should be exported as mp4")
        try expect(FileManager.default.fileExists(atPath: result.outputDirectory.appendingPathComponent("视频02.mp4").path), "second video should be converted to mp4")
        try expect(!FileManager.default.fileExists(atPath: result.outputDirectory.appendingPathComponent("视频02.mov").path), "mov source should not export as mov")
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

    private static func makeVideoFile(at url: URL, fileType: AVFileType) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: fileType)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 16,
                AVVideoHeightKey: 16
            ]
        )
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 16,
                kCVPixelBufferHeightKey as String: 16
            ]
        )
        guard writer.canAdd(input) else {
            throw TestFailure("failed to add video writer input")
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw TestFailure(writer.error?.localizedDescription ?? "failed to start video writer")
        }
        writer.startSession(atSourceTime: .zero)
        guard let pool = adaptor.pixelBufferPool else {
            throw TestFailure("failed to create pixel buffer pool")
        }
        var maybeBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &maybeBuffer)
        guard let buffer = maybeBuffer else {
            throw TestFailure("failed to create pixel buffer")
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
            memset(baseAddress, 0x40, CVPixelBufferGetDataSize(buffer))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        while !input.isReadyForMoreMediaData {
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard adaptor.append(buffer, withPresentationTime: .zero) else {
            throw TestFailure(writer.error?.localizedDescription ?? "failed to append video frame")
        }
        input.markAsFinished()
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting {
            semaphore.signal()
        }
        semaphore.wait()
        guard writer.status == .completed else {
            throw TestFailure(writer.error?.localizedDescription ?? "failed to finish video writer")
        }
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
