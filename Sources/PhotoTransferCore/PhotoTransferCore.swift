import AppKit
import Foundation
import UniformTypeIdentifiers

public struct OrderedPhoto: Identifiable, Hashable {
    public let id: UUID
    public let sourceURL: URL

    public init(id: UUID = UUID(), sourceURL: URL) {
        self.id = id
        self.sourceURL = sourceURL
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
        }
    }
}

public enum ExportNamer {
    public static func fileName(folderName: String, index: Int, totalCount: Int) -> String {
        let width = max(2, String(totalCount).count)
        return "\(folderName)\(String(format: "%0\(width)d", index)).jpg"
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
        let total = selectedPhotos.count
        var exportedCount = 0
        var failedItems: [URL] = []

        for (offset, photo) in selectedPhotos.enumerated() {
            let fileName = ExportNamer.fileName(folderName: cleanName, index: offset + 1, totalCount: total)
            let outputURL = outputDirectory.appendingPathComponent(fileName)
            do {
                guard let jpgData = try JPEGConverter.jpegData(from: photo.sourceURL) else {
                    failedItems.append(photo.sourceURL)
                    continue
                }
                try jpgData.write(to: outputURL, options: .atomic)
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

public enum ImageFileDetector {
    public static func isSupportedImageURL(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else {
            return false
        }
        return type.conforms(to: .image)
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
