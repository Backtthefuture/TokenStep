import AppKit
import SwiftUI

@main
struct UsageRecalibrationNoticeRender {
    @MainActor
    static func main() throws {
        TokenStepLocalization.apply(.zhHans)
        let outputPath = ProcessInfo.processInfo.environment["TOKENSTEP_NOTICE_RENDER_PATH"]
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("tokenstep-usage-recalibration-notice.png")
                .path
        let content = UsageRecalibrationNotice(dismiss: {})
            .padding(20)
            .frame(width: 412)
            .background(Color.tokenCanvas)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            throw NSError(
                domain: "UsageRecalibrationNoticeRender",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to render migration notice"]
            )
        }
        try png.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        print(outputPath)
    }
}
