import AppKit
import SwiftUI

// G-V1 / V1-T02：九个 fixture 状态的渲染件（MG-UX 人工门材料）。
// 与 PRD §5.3 验收 fixtures 一一对应，渲染为单张 PNG 供审核。
@main
struct FreshnessStatesRender {
    @MainActor
    static func main() throws {
        let now = Date()
        let outputURL = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["TOKENSTEP_FRESHNESS_RENDER_PATH"]
                ?? "/tmp/tokenstep-freshness-states.png"
        ).standardizedFileURL
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let rows: [(String, UsageFreshness)] = [
            (
                "1. 首次启动（从未成功）",
                FreshnessPolicy.classify(
                    enabled: true,
                    record: RefreshAttemptRecord().attempting(at: now.addingTimeInterval(-30)),
                    normalTTL: 300,
                    now: now
                )
            ),
            (
                "2. 刚成功",
                FreshnessPolicy.classify(
                    enabled: true,
                    record: RefreshAttemptRecord(lastSucceededAt: now.addingTimeInterval(-10)),
                    normalTTL: 300,
                    now: now
                )
            ),
            (
                "3. 数据老化（超 TTL 未失败）",
                FreshnessPolicy.classify(
                    enabled: true,
                    record: RefreshAttemptRecord(lastSucceededAt: now.addingTimeInterval(-420)),
                    normalTTL: 300,
                    now: now
                )
            ),
            (
                "4. 额度请求失败有旧值（网络）",
                FreshnessPolicy.classify(
                    enabled: true,
                    record: RefreshAttemptRecord(lastSucceededAt: now.addingTimeInterval(-60))
                        .attempting(at: now.addingTimeInterval(-5))
                        .failing(kind: .networkFailed, at: now.addingTimeInterval(-5)),
                    normalTTL: FreshnessPolicy.quotaNormalTTL,
                    now: now
                )
            ),
            (
                "5. 采集失败有旧快照",
                FreshnessPolicy.classify(
                    enabled: true,
                    record: RefreshAttemptRecord(lastSucceededAt: now.addingTimeInterval(-120))
                        .failing(kind: .collectionFailed, at: now.addingTimeInterval(-3)),
                    normalTTL: 300,
                    now: now
                )
            ),
            (
                "6a. Codex 额度成功",
                FreshnessPolicy.classify(
                    enabled: true,
                    record: RefreshAttemptRecord(lastSucceededAt: now.addingTimeInterval(-10)),
                    normalTTL: FreshnessPolicy.quotaNormalTTL,
                    now: now
                )
            ),
            (
                "6b. Claude 额度失败（凭据）",
                FreshnessPolicy.classify(
                    enabled: true,
                    record: RefreshAttemptRecord(lastSucceededAt: now.addingTimeInterval(-60))
                        .failing(kind: .unauthorized, at: now.addingTimeInterval(-1)),
                    normalTTL: FreshnessPolicy.quotaNormalTTL,
                    now: now
                )
            ),
            (
                "7. 部分本地源失败",
                FreshnessPolicy.classify(
                    enabled: true,
                    record: RefreshAttemptRecord(lastSucceededAt: now.addingTimeInterval(-10)),
                    normalTTL: 300,
                    now: now,
                    sourceStatuses: [
                        "Codex": "ok",
                        "Claude Code": "ok",
                        "CC Switch via proxy": "incremental_cache_error",
                        "ZCode": "disabled"
                    ]
                )
            ),
            (
                "8. 额度功能关闭",
                FreshnessPolicy.classify(
                    enabled: false,
                    record: RefreshAttemptRecord(lastSucceededAt: now),
                    normalTTL: FreshnessPolicy.quotaNormalTTL,
                    now: now
                )
            ),
            (
                "9. 旧快照读取（新字段缺失按 nil 兼容）",
                FreshnessPolicy.classify(
                    enabled: true,
                    record: RefreshAttemptRecord(lastSucceededAt: now.addingTimeInterval(-10)),
                    normalTTL: 300,
                    now: now
                )
            )
        ]

        let content = VStack(alignment: .leading, spacing: 16) {
            Text("TokenStep 数据状态 fixtures（G-V1 / V1-T02）")
                .font(.system(size: 17, weight: .heavy))
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]
                HStack(spacing: 14) {
                    Text(row.0)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.tokenInk.opacity(0.72))
                        .frame(width: 250, alignment: .leading)
                    FreshnessBadge(
                        freshness: row.1,
                        showsLastSucceeded: row.1.needsAttention
                    )
                    Spacer()
                }
            }
            Text("金额示例：消耗金额（估算）$12.34 · 按 API 列表价估算，不代表订阅或实际账单。")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 640)
        .background(Color.white)
        .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            throw NSError(
                domain: "FreshnessStatesRender",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to render freshness states"]
            )
        }
        try png.write(to: outputURL, options: .atomic)
        print(outputURL.path)
    }
}
