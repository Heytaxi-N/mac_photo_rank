import AppKit
import AVFoundation
import Foundation
import UniformTypeIdentifiers

public enum MediaKind: Hashable {
    case image
    case video
}

public struct OrderedPhoto: Identifiable, Hashable {
    public let id: UUID
    public let sourceURL: URL
    public let kind: MediaKind

    public init(id: UUID = UUID(), sourceURL: URL, kind: MediaKind = .image) {
        self.id = id
        self.sourceURL = sourceURL
        self.kind = kind
    }
}

public struct PhotoOrder: Hashable {
    public private(set) var orderedIDs: [UUID]

    public init(orderedIDs: [UUID] = []) {
        self.orderedIDs = []
        for id in orderedIDs where !self.orderedIDs.contains(id) {
            self.orderedIDs.append(id)
        }
    }

    public mutating func toggle(_ id: UUID) {
        if let index = orderedIDs.firstIndex(of: id) {
            orderedIDs.remove(at: index)
        } else {
            orderedIDs.append(id)
        }
    }

    public mutating func clear() {
        orderedIDs.removeAll()
    }

    public func number(for id: UUID) -> Int? {
        guard let index = orderedIDs.firstIndex(of: id) else {
            return nil
        }
        return index + 1
    }
}

public enum ExportConflictResolution: Equatable {
    case cancelIfExists
    case overwrite
    case createUniqueFolder
}

public enum ExportError: LocalizedError, Equatable {
    case emptyFolderName
    case noSelectedPhotos
    case destinationExists(URL)
    case cannotCreateJPEG(URL)
    case cannotCreateVideo(URL)

    public var errorDescription: String? {
        switch self {
        case .emptyFolderName:
            return "请输入文件夹名。"
        case .noSelectedPhotos:
            return "请至少给一张图片编号。"
        case .destinationExists(let url):
            return "目标文件夹已存在：\(url.path)"
        case .cannotCreateJPEG(let url):
            return "无法转换为 JPG：\(url.lastPathComponent)"
        case .cannotCreateVideo(let url):
            return "无法转换为 MP4：\(url.lastPathComponent)"
        }
    }
}

public enum ExportNamer {
    public static func fileName(folderName: String, index: Int, totalCount: Int, hasSizeChart: Bool = false) -> String {
        if hasSizeChart, index == totalCount {
            return "尺码表.jpg"
        }
        let width = max(2, String(totalCount).count)
        return "\(folderName)\(String(format: "%0\(width)d", index)).jpg"
    }

    public static func videoFileName(index: Int, totalCount: Int, pathExtension: String) -> String {
        let width = max(2, String(totalCount).count)
        let baseName = "视频\(String(format: "%0\(width)d", index))"
        guard !pathExtension.isEmpty else {
            return baseName
        }
        return "\(baseName).\(pathExtension)"
    }
}

public enum ExportDestination {
    public static func resolveFolder(
        rootDirectory: URL,
        folderName: String,
        conflictResolution: ExportConflictResolution,
        fileManager: FileManager = .default
    ) throws -> URL {
        let cleanName = sanitizeFolderName(folderName)
        guard !cleanName.isEmpty else {
            throw ExportError.emptyFolderName
        }

        let requested = rootDirectory.appendingPathComponent(cleanName, isDirectory: true)
        guard fileManager.fileExists(atPath: requested.path) else {
            return requested
        }

        switch conflictResolution {
        case .cancelIfExists:
            throw ExportError.destinationExists(requested)
        case .overwrite:
            return requested
        case .createUniqueFolder:
            var suffix = 2
            while true {
                let candidate = rootDirectory.appendingPathComponent("\(cleanName)-\(suffix)", isDirectory: true)
                if !fileManager.fileExists(atPath: candidate.path) {
                    return candidate
                }
                suffix += 1
            }
        }
    }

    public static func sanitizeFolderName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalidCharacters = CharacterSet(charactersIn: "/:")
        return trimmed
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
    }
}

public struct ExportResult: Equatable {
    public let outputDirectory: URL
    public let exportedCount: Int
    public let skippedCount: Int
    public let failedItems: [URL]
}

public enum PhotoExporter {
    public static let defaultRootDirectory = URL(fileURLWithPath: "/Users/nick/Downloads/weidian_products-main/商品图", isDirectory: true)

    public static func export(
        photos: [OrderedPhoto],
        order: PhotoOrder,
        folderName: String,
        rootDirectory: URL = defaultRootDirectory,
        hasSizeChart: Bool = false,
        conflictResolution: ExportConflictResolution
    ) throws -> ExportResult {
        let cleanName = ExportDestination.sanitizeFolderName(folderName)
        guard !cleanName.isEmpty else {
            throw ExportError.emptyFolderName
        }
        guard !order.orderedIDs.isEmpty else {
            throw ExportError.noSelectedPhotos
        }

        let outputDirectory = try ExportDestination.resolveFolder(
            rootDirectory: rootDirectory,
            folderName: cleanName,
            conflictResolution: conflictResolution
        )

        if conflictResolution == .overwrite, FileManager.default.fileExists(atPath: outputDirectory.path) {
            try FileManager.default.removeItem(at: outputDirectory)
        }
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let photoByID = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
        let selectedPhotos = order.orderedIDs.compactMap { photoByID[$0] }
        let totalImages = selectedPhotos.filter { $0.kind == .image }.count
        let totalVideos = selectedPhotos.filter { $0.kind == .video }.count
        var imageIndex = 0
        var videoIndex = 0
        var exportedCount = 0
        var failedItems: [URL] = []

        for photo in selectedPhotos {
            do {
                switch photo.kind {
                case .image:
                    imageIndex += 1
                    let fileName = ExportNamer.fileName(folderName: cleanName, index: imageIndex, totalCount: totalImages, hasSizeChart: hasSizeChart)
                    let outputURL = outputDirectory.appendingPathComponent(fileName)
                    guard let jpgData = try JPEGConverter.jpegData(from: photo.sourceURL) else {
                        failedItems.append(photo.sourceURL)
                        continue
                    }
                    try jpgData.write(to: outputURL, options: .atomic)
                case .video:
                    videoIndex += 1
                    let fileName = ExportNamer.videoFileName(index: videoIndex, totalCount: totalVideos, pathExtension: "mp4")
                    let outputURL = outputDirectory.appendingPathComponent(fileName)
                    try VideoConverter.exportMP4(from: photo.sourceURL, to: outputURL)
                }
                exportedCount += 1
            } catch {
                failedItems.append(photo.sourceURL)
            }
        }

        return ExportResult(
            outputDirectory: outputDirectory,
            exportedCount: exportedCount,
            skippedCount: photos.count - selectedPhotos.count,
            failedItems: failedItems
        )
    }
}

enum VideoConverter {
    static func exportMP4(from sourceURL: URL, to outputURL: URL) throws {
        if sourceURL.pathExtension.lowercased() == "mp4" {
            try FileManager.default.copyItem(at: sourceURL, to: outputURL)
            return
        }

        let asset = AVURLAsset(url: sourceURL)
        var lastError: Error?

        for preset in [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality] {
            guard let session = AVAssetExportSession(asset: asset, presetName: preset),
                  session.supportedFileTypes.contains(.mp4)
            else {
                continue
            }
            do {
                try runExport(session, outputURL: outputURL)
                return
            } catch {
                lastError = error
                try? FileManager.default.removeItem(at: outputURL)
            }
        }

        throw lastError ?? ExportError.cannotCreateVideo(sourceURL)
    }

    private static func runExport(_ session: AVAssetExportSession, outputURL: URL) throws {
        session.outputURL = outputURL
        session.outputFileType = .mp4

        let semaphore = DispatchSemaphore(value: 0)
        session.exportAsynchronously {
            semaphore.signal()
        }
        semaphore.wait()

        guard session.status == .completed else {
            throw session.error ?? ExportError.cannotCreateVideo(outputURL)
        }
    }
}

public enum MediaFileDetector {
    private static let fallbackVideoExtensions: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "webm"]

    public static func kind(for url: URL) -> MediaKind? {
        let pathExtension = url.pathExtension.lowercased()
        if let type = UTType(filenameExtension: pathExtension) {
            if type.conforms(to: .image) {
                return .image
            }
            if type.conforms(to: .movie) {
                return .video
            }
        }
        if fallbackVideoExtensions.contains(pathExtension) {
            return .video
        }
        return nil
    }
}

public enum ImageFileDetector {
    public static func isSupportedImageURL(_ url: URL) -> Bool {
        MediaFileDetector.kind(for: url) == .image
    }
}

public enum VideoFileDetector {
    public static func isSupportedVideoURL(_ url: URL) -> Bool {
        MediaFileDetector.kind(for: url) == .video
    }
}

enum JPEGConverter {
    static func jpegData(from url: URL, compressionFactor: CGFloat = 0.92) throws -> Data? {
        guard let image = NSImage(contentsOf: url) else {
            return nil
        }
        return jpegData(from: image, compressionFactor: compressionFactor)
    }

    static func jpegData(from image: NSImage, compressionFactor: CGFloat = 0.92) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: compressionFactor])
    }
}
