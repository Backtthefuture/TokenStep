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
        // 断言 1：来源卡自然高度应为有限正值（自适应模式不再被裁剪）。
        guard sourcesSize.height > 300, sourcesSize.height < 1200 else {
            throw NSError(domain: "SettingsCardsRender", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "sources card height out of range: \(sourcesSize.height)"
            ])
        }
        // 断言 2：榜单卡分段选择器必须有"墨水"——
        // macOS 15 下空标题/labelsHidden 会连分段文字一起隐藏（2026-08-14 真机回归）。
        guard let pngData = try? Data(contentsOf: outputURL),
              let rankPNG = NSBitmapImageRep(data: pngData) else {
            throw NSError(domain: "SettingsCardsRender", code: 4)
        }
        // 组合渲染为 @2x 位图；矩形直接用图像像素坐标（榜单卡 picker 带）。
        let pickerInk = countDarkPixels(
            in: rankPNG,
            rect: CGRect(x: 230, y: 1195, width: 670, height: 105),
            scale: 1
        )
        guard pickerInk > 100 else {
            throw NSError(domain: "SettingsCardsRender", code: 5, userInfo: [
                NSLocalizedDescriptionKey: "rank picker band has no ink (segmented labels missing?): \(pickerInk)"
            ])
        }
        print("rank picker ink: \(pickerInk)")
    }
}


private func countDarkPixels(in rep: NSBitmapImageRep, rect: CGRect, scale: CGFloat) -> Int {
    let xStart = Int(Double(rect.minX) * Double(scale))
    let xEnd = Int(Double(rect.maxX) * Double(scale))
    let yStart = Int(Double(rect.minY) * Double(scale))
    let yEnd = Int(Double(rect.maxY) * Double(scale))
    let xRange = xStart..<max(xStart + 1, xEnd)
    let yRange = yStart..<max(yStart + 1, yEnd)
    var count = 0
    for y in yRange where y >= 0 && y < rep.pixelsHigh {
        for x in xRange where x >= 0 && x < rep.pixelsWide {
            if let color = rep.colorAt(x: x, y: y) {
                let brightness = (color.redComponent + color.greenComponent + color.blueComponent) / 3
                if brightness < 0.6 { count += 1 }
            }
        }
    }
    return count
}
