import AppKit
import PhotoTransferCore
import SwiftUI
import UniformTypeIdentifiers

@main
struct PhotoTransferApp: App {
    var body: some Scene {
        WindowGroup {
            PhotoTransferView()
                .frame(minWidth: 920, minHeight: 640)
        }
        .windowStyle(.titleBar)
    }
}

struct PhotoTransferView: View {
    @StateObject private var model = PhotoTransferViewModel()

    private let columns = [
        GridItem(.adaptive(minimum: 128, maximum: 168), spacing: 14)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            dropAndGrid
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .confirmationDialog("目标文件夹已存在", isPresented: $model.showConflictDialog, titleVisibility: .visible) {
            Button("覆盖并重新导出", role: .destructive) {
                model.export(conflictResolution: .overwrite)
            }
            Button("自动新建后缀文件夹") {
                model.export(conflictResolution: .createUniqueFolder)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("选择覆盖会先清空旧文件夹，避免残留旧商品图。")
        }
        .alert("导出结果", isPresented: $model.showResultAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text(model.resultMessage)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("商品图转存")
                    .font(.title3.weight(.semibold))
                Text(PhotoExporter.defaultRootDirectory.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 18)

            TextField("文件夹名，例如 红标短裤", text: $model.folderName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .onSubmit {
                    model.prepareExport()
                }

            Button {
                model.clearOrder()
            } label: {
                Label("重排", systemImage: "arrow.counterclockwise")
            }
            .disabled(model.selectedCount == 0)

            Button {
                model.clearAll()
            } label: {
                Label("清空", systemImage: "trash")
            }
            .disabled(model.photos.isEmpty)

            Button {
                model.prepareExport()
            } label: {
                Label("导出", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canExport)
        }
        .padding(18)
    }

    private var dropAndGrid: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(model.isDropTargeted ? Color.accentColor : Color(nsColor: .separatorColor), style: StrokeStyle(lineWidth: model.isDropTargeted ? 2 : 1, dash: [7, 5]))
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(model.isDropTargeted ? Color.accentColor.opacity(0.08) : Color(nsColor: .textBackgroundColor))
                )
                .padding(16)

            if model.photos.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 44, weight: .regular))
                        .foregroundStyle(.secondary)
                    Text("从「照片」或 Finder 拖入图片")
                        .font(.title3.weight(.medium))
                    Text("拖入后按目标顺序点击缩略图，未编号图片不会导出。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(model.photos) { item in
                            PhotoTileView(
                                item: item,
                                number: model.number(for: item.id),
                                isSelected: model.number(for: item.id) != nil
                            )
                            .onTapGesture {
                                model.toggle(item.id)
                            }
                        }
                    }
                    .padding(28)
                }
            }
        }
        .onDrop(of: model.acceptedTypeIdentifiers, isTargeted: $model.isDropTargeted) { providers in
            model.addProviders(providers)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Label("\(model.photos.count) 张已导入", systemImage: "photo.stack")
            Label("\(model.selectedCount) 张已编号", systemImage: "number")
            if model.ignoredDropCount > 0 {
                Label("\(model.ignoredDropCount) 个文件已忽略", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            Spacer()
            Text(model.statusText)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.callout)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct PhotoTileView: View {
    let item: PhotoTile
    let number: Int?
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: item.thumbnail)
                .resizable()
                .scaledToFill()
                .frame(height: 132)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                }
                .opacity(isSelected ? 1 : 0.62)

            if let number {
                Text(String(format: "%02d", number))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.accentColor, in: Capsule())
                    .padding(8)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .help(item.sourceURL.lastPathComponent)
    }
}

struct PhotoTile: Identifiable, Hashable {
    let id: UUID
    let sourceURL: URL
    let thumbnail: NSImage

    var orderedPhoto: OrderedPhoto {
        OrderedPhoto(id: id, sourceURL: sourceURL)
    }
}

@MainActor
final class PhotoTransferViewModel: ObservableObject {
    @Published var folderName = ""
    @Published var photos: [PhotoTile] = []
    @Published var order = PhotoOrder()
    @Published var isDropTargeted = false
    @Published var ignoredDropCount = 0
    @Published var resultMessage = ""
    @Published var showResultAlert = false
    @Published var showConflictDialog = false

    let acceptedTypeIdentifiers = [
        UTType.fileURL.identifier,
        UTType.image.identifier,
        UTType.jpeg.identifier,
        UTType.png.identifier,
        UTType.tiff.identifier,
        "com.apple.photos.asset-bundle"
    ]

    var selectedCount: Int {
        order.orderedIDs.count
    }

    var canExport: Bool {
        !ExportDestination.sanitizeFolderName(folderName).isEmpty && selectedCount > 0
    }

    var statusText: String {
        if photos.isEmpty {
            return "等待拖入图片"
        }
        if selectedCount == 0 {
            return "点击缩略图开始编号"
        }
        return "将导出 \(selectedCount) 张 JPG"
    }

    func number(for id: UUID) -> Int? {
        order.number(for: id)
    }

    func toggle(_ id: UUID) {
        order.toggle(id)
    }

    func clearOrder() {
        order.clear()
    }

    func clearAll() {
        photos.removeAll()
        order.clear()
        ignoredDropCount = 0
    }

    func addProviders(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                accepted = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
                    guard let url = Self.fileURL(from: item) else {
                        DispatchQueue.main.async { self?.ignoredDropCount += 1 }
                        return
                    }
                    DispatchQueue.main.async {
                        self?.addImageURL(url)
                    }
                }
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                accepted = true
                provider.loadObject(ofClass: NSImage.self) { [weak self] object, _ in
                    guard let image = object as? NSImage, let url = Self.writeTemporaryImage(image) else {
                        DispatchQueue.main.async { self?.ignoredDropCount += 1 }
                        return
                    }
                    DispatchQueue.main.async {
                        self?.addImageURL(url, thumbnail: image)
                    }
                }
            } else {
                ignoredDropCount += 1
            }
        }

        return accepted
    }

    func prepareExport() {
        let cleanName = ExportDestination.sanitizeFolderName(folderName)
        guard !cleanName.isEmpty else {
            showMessage("请输入文件夹名。")
            return
        }
        guard selectedCount > 0 else {
            showMessage("请先按顺序点击要导出的图片。")
            return
        }

        let requestedFolder = PhotoExporter.defaultRootDirectory.appendingPathComponent(cleanName, isDirectory: true)
        if FileManager.default.fileExists(atPath: requestedFolder.path) {
            showConflictDialog = true
        } else {
            export(conflictResolution: .cancelIfExists)
        }
    }

    func export(conflictResolution: ExportConflictResolution) {
        do {
            let result = try PhotoExporter.export(
                photos: photos.map(\.orderedPhoto),
                order: order,
                folderName: folderName,
                conflictResolution: conflictResolution
            )

            var message = "已导出 \(result.exportedCount) 张图片到：\n\(result.outputDirectory.path)"
            if result.skippedCount > 0 {
                message += "\n未编号图片：\(result.skippedCount) 张"
            }
            if !result.failedItems.isEmpty {
                message += "\n转换失败：\(result.failedItems.count) 张"
            }
            showMessage(message)
        } catch {
            showMessage((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func addImageURL(_ url: URL, thumbnail providedThumbnail: NSImage? = nil) {
        let normalizedURL = url.standardizedFileURL
        guard photos.contains(where: { $0.sourceURL == normalizedURL }) == false else {
            return
        }
        guard let thumbnail = providedThumbnail ?? NSImage(contentsOf: normalizedURL) else {
            ignoredDropCount += 1
            return
        }

        photos.append(PhotoTile(id: UUID(), sourceURL: normalizedURL, thumbnail: thumbnail))
    }

    private func showMessage(_ message: String) {
        resultMessage = message
        showResultAlert = true
    }

    nonisolated private static func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let url = item as? NSURL {
            return url as URL
        }
        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }
        if let string = item as? String {
            return URL(string: string)
        }
        return nil
    }

    nonisolated private static func writeTemporaryImage(_ image: NSImage) -> URL? {
        guard
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
            let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
        else {
            return nil
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoTransferDrops", isDirectory: true)
        let url = directory.appendingPathComponent("\(UUID().uuidString).png")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
