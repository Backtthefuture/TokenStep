import Foundation

enum TokenStepError: LocalizedError {
    case collectorFailed(status: Int32, message: String)
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .collectorFailed(status, message):
            if message.isEmpty {
                return LFormat("采集脚本退出码 %d", status)
            }
            return LFormat("采集脚本退出码 %d：%@", status, message)
        case let .message(message):
            return message
        }
    }
}
