import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct ScreenshotRenderingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isScreenshotRendering: Bool {
        get { self[ScreenshotRenderingKey.self] }
        set { self[ScreenshotRenderingKey.self] = newValue }
    }
}

enum ScreenshotExportError: LocalizedError {
    case renderFailed
    case pngEncodingFailed
    case jpgEncodingFailed

    var errorDescription: String? {
        switch self {
        case .renderFailed:
            return L("截图生成失败，请稍后再试。")
        case .pngEncodingFailed:
            return L("PNG 文件生成失败，请稍后再试。")
        case .jpgEncodingFailed:
            return L("JPG 文件生成失败，请稍后再试。")
        }
    }
}

@MainActor
enum ScreenshotExporter {
    static func copy<V: View>(_ view: V) throws {
        defer { MemoryPressure.relieveAllocatorPressure() }
        let image = try render(view)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    static func save<V: View>(_ view: V, suggestedFileName: String) throws {
        defer { MemoryPressure.relieveAllocatorPressure() }
        let image = try render(view)
        let data = try pngData(from: image)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = suggestedFileName

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try data.write(to: url, options: .atomic)
    }

    @discardableResult
    static func saveJPGToDownloads<V: View>(_ view: V) throws -> URL {
        defer { MemoryPressure.relieveAllocatorPressure() }
        let image = try render(view)
        let data = try jpgData(from: image)
        let url = try uniqueDownloadsURL()
        try data.write(to: url, options: .atomic)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return url
    }

    static func suggestedFileName(prefix: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return "TokenStep-\(prefix)-\(formatter.string(from: Date())).png"
    }

    private static func render<V: View>(_ view: V) throws -> NSImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else {
            throw ScreenshotExportError.renderFailed
        }
        return image
    }

    private static func pngData(from image: NSImage) throws -> Data {
        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let data = bitmap.representation(using: .png, properties: [:])
        else {
            throw ScreenshotExportError.pngEncodingFailed
        }
        return data
    }

    private static func jpgData(from image: NSImage) throws -> Data {
        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let data = bitmap.representation(
                using: .jpeg,
                properties: [.compressionFactor: 0.94]
            )
        else {
            throw ScreenshotExportError.jpgEncodingFailed
        }
        return data
    }

    private static func uniqueDownloadsURL() throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyMMdd"
        let baseName = "TokenStep\(formatter.string(from: Date()))"

        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")

        var candidate = downloads.appendingPathComponent("\(baseName).jpg")
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = downloads.appendingPathComponent("\(baseName)-\(index).jpg")
            index += 1
        }
        return candidate
    }
}
