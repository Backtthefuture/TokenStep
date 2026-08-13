import SwiftUI

struct PrivacyView: View {
    var body: some View {
        VStack(spacing: 22) {
            TokenCard {
                VStack(alignment: .leading, spacing: 20) {
                    Text(L("本地优先"))
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(Color.tokenInk)
                    PrivacyRow(index: 1, title: L("只统计 token 数量"), description: L("用于计算今日 Token 消耗、历史趋势和消耗金额。"))
                    PrivacyRow(index: 2, title: L("不上传代码或对话"), description: L("所有数据文件都保留在这台 Mac 上。"))
                    PrivacyRow(index: 3, title: L("消耗金额仅供参考"), description: L("按本地价格表粗略估算，不等于真实账单。"))
                }
            }

            TokenCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L("本地文件"))
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(Color.tokenInk)
                    FilePathRow(label: L("用量数据"), path: AppPaths.usageJSON.path)
                    FilePathRow(label: L("设置"), path: AppPaths.settingsJSON.path)
                    Text(L("后续如果接入排行榜，会单独做授权和确认，不会默认上传。"))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .textSelection(.enabled)
            }

            TokenCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L("数据状态说明"))
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(Color.tokenInk)
                    // G-V1：与浮层、主窗口和 docs/DATA_TRUST.md 使用同一套术语。
                    VStack(alignment: .leading, spacing: 10) {
                        statusLegend(symbol: "checkmark.circle.fill", color: .tokenGreen,
                                     title: L("已同步"),
                                     description: L("数据在正常刷新周期内成功获取。"))
                        statusLegend(symbol: "clock.fill", color: .orange,
                                     title: L("数据待更新"),
                                     description: L("超过正常刷新周期，最近一次尝试没有失败。"))
                        statusLegend(symbol: "exclamationmark.triangle.fill", color: .red,
                                     title: L("同步失败"),
                                     description: L("最近一次尝试失败，当前展示最后成功数据。"))
                        statusLegend(symbol: "exclamationmark.arrow.triangle.2.circlepath", color: .orange,
                                     title: L("部分来源失败"),
                                     description: L("同一轮刷新中部分数据来源失败，其余正常。"))
                        statusLegend(symbol: "circle.dashed", color: .secondary,
                                     title: L("暂无数据"),
                                     description: L("该数据从未成功获取，不会显示为 0。"))
                    }
                    Text(L("按 API 列表价估算，不代表订阅或实际账单。"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func statusLegend(symbol: String, color: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.heavy))
                    .foregroundStyle(Color.tokenInk)
                Text(description)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct PrivacyRow: View {
    var index: Int
    var title: String
    var description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text("\(index)")
                .font(.headline.weight(.heavy))
                .foregroundStyle(Color.tokenGreen)
                .frame(width: 34, height: 34)
                .background(Color.tokenGreen.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.tokenInk)
                Text(description)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct FilePathRow: View {
    var label: String
    var path: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(path)
                .font(.callout.monospaced().weight(.semibold))
                .foregroundStyle(Color.tokenInk.opacity(0.76))
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tokenTrack.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
