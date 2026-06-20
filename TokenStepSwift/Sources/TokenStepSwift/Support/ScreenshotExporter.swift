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

    var errorDescription: String? {
        switch self {
        case .renderFailed:
            return L("截图生成失败，请稍后再试。")
        case .pngEncodingFailed:
            return L("PNG 文件生成失败，请稍后再试。")
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
}
