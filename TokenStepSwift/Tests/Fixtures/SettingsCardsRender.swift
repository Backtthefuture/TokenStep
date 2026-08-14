import AppKit
import SwiftUI

// 设置页两张卡片的渲染测量（自适应高度验证）：打印自然高度并落 PNG。
@main
struct SettingsCardsRender {
    @MainActor
    static func main() throws {
        let appState = AppState()
        let outputURL = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["TOKENSTEP_SETTINGS_RENDER_PATH"]
                ?? "/tmp/tokenstep-settings-cards.png"
        ).standardizedFileURL
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        func measure<V: View>(_ view: V, width: CGFloat, label: String) throws -> CGSize {
            let sized = view
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true)
                .environmentObject(appState)
                .environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: sized)
            renderer.scale = 1
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:])
            else {
                throw NSError(domain: "SettingsCardsRender", code: 1)
            }
            let size = CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
            print("\(label): \(Int(size.width))x\(Int(size.height))")
            _ = png
            return size
        }

        let sourcesSize = try measure(SettingsAgentSourcesCard(), width: 840, label: "sources-card")
        _ = try measure(SettingsTokenRankCard(), width: 406, label: "rank-card")

        let content = VStack(spacing: 18) {
            SettingsAgentSourcesCard().frame(width: 840)
            HStack(alignment: .top, spacing: 18) {
                SettingsTokenRankCard()
                SettingsRefreshCard()
            }
        }
        .padding(24)
        .background(Color.white)
        .environmentObject(appState)
        .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            throw NSError(domain: "SettingsCardsRender", code: 2)
        }
        try png.write(to: outputURL, options: .atomic)
        print("combined render: \(bitmap.pixelsWide/2)x\(bitmap.pixelsHigh/2) -> \(outputURL.path)")
        // 断言：来源卡自然高度应为有限正值（自适应模式不再被 460 裁剪）。
        guard sourcesSize.height > 300, sourcesSize.height < 1200 else {
            throw NSError(domain: "SettingsCardsRender", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "sources card height out of range: \(sourcesSize.height)"
            ])
        }
    }
}
