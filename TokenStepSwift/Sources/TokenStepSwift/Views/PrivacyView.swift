import SwiftUI

struct PrivacyView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 12) {
            TokenCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("本地优先"))
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(Color.tokenInk)
                    Text(L("默认不联网、不上传。Token 统计全部来自本机日志。"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    PrivacyFactRow(title: L("读取"), value: L("日期 · 模型名 · 客户端名 · token 计数"))
                    PrivacyFactRow(title: L("不读取"), value: L("prompt · 代码正文 · 对话内容"))
                    PrivacyFactRow(title: L("不做"), value: L("不开代理 · 不按字数估算 token"))
                }
            }

            HStack(alignment: .top, spacing: 13) {
                TokenCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("联网项（全部默认关闭）"))
                            .font(.title3.weight(.heavy))
                            .foregroundStyle(Color.tokenInk)
                        Text(L("开启后才会发起请求，逐项独立"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        PrivacyNetworkRow(badge: "L2", style: .l2, title: L("Codex 额度"), detail: L("本机 codex 登录态"))
                        PrivacyNetworkRow(badge: "L2", style: .l2, title: L("Claude 额度"), detail: L("钥匙串 OAuth → Anthropic"))
                        PrivacyNetworkRow(badge: "L2", style: .l2, title: L("Cursor 额度与官方用量"), detail: L("state.vscdb → cursor.com 事件计入圆环"))
                        PrivacyNetworkRow(badge: "L2", style: .l2, title: L("GLM / Kimi / Grok"), detail: L("各自本机凭证"))
                        PrivacyNetworkRow(badge: L("榜"), style: .ok, title: L("消耗榜"), detail: L("仅在开启后上报"))
                    }
                }

                TokenCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text(L("Cursor 明细"))
                                .font(.title3.weight(.heavy))
                                .foregroundStyle(Color.tokenInk)
                            SettingsBadge(text: L("L3 本地"), style: .l3)
                        }
                        Text(L("额度走网络；官方用量事件计入圆环；代码产出纯本地。"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        PrivacyFactRow(title: L("读 accessToken"), value: L("仅内存 · 不落盘不上传"))
                        PrivacyFactRow(title: L("读代码块计数"), value: L("ai_code_hashes 的 count 与 model"))
                        PrivacyFactRow(title: L("明确不读"), value: L("tracked_file_content（代码正文）"), emphasis: true)
                        PrivacyFactRow(title: L("明确不读"), value: L("conversation_summaries（对话摘要）"), emphasis: true)
                        Text(L("Cursor 的用量接口非官方公开契约，可能随时变更。失效时只影响这一项。"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color(red: 0.42, green: 0.36, blue: 0.82).opacity(0.16))
                )
            }

            TokenCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("本地文件"))
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(Color.tokenInk)
                    Text(L("可直接查看或删除"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("\(AppPaths.usageJSON.path)\n\(AppPaths.settingsJSON.path)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.tokenTrack.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text(L("今日花费含本地估算，以及已开启的 Cursor 官方 charged 金额。额度栏里的美元/百分比不要和圆环花费加在一起。"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 9) {
                        Button {
                            appState.revealLocalDataInFinder()
                        } label: {
                            Text(L("在 Finder 中显示"))
                                .font(.callout.weight(.bold))
                                .padding(.horizontal, 14)
                                .frame(height: 36)
                        }
                        .buttonStyle(SettingsSecondaryButtonStyle())

                        Button {
                            appState.clearLocalUsageData()
                        } label: {
                            Text(L("清除本地数据"))
                                .font(.callout.weight(.bold))
                                .padding(.horizontal, 14)
                                .frame(height: 36)
                        }
                        .buttonStyle(SettingsSecondaryButtonStyle())
                    }
                }
            }
        }
    }
}

private struct PrivacyFactRow: View {
    var title: String
    var value: String
    var emphasis = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.tokenInk)
            Spacer(minLength: 12)
            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(emphasis ? Color(red: 0.56, green: 0.21, blue: 0.09) : Color.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 7)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .frame(height: 1)
        }
    }
}

private struct PrivacyNetworkRow: View {
    var badge: String
    var style: SettingsBadgeStyle
    var title: String
    var detail: String

    var body: some View {
        HStack(spacing: 8) {
            SettingsBadge(text: badge, style: style)
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.tokenInk)
            Spacer()
            Text(detail)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 7)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .frame(height: 1)
        }
    }
}
