import Foundation

enum HTTPJSONClient {
    static var transport: (URLRequest) throws -> (Data, URLResponse) = defaultTransport

    static func data(for request: URLRequest) throws -> Data {
        let (data, response) = try transport(request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TokenStepError.message("HTTP \(http.statusCode)")
        }
        return data
    }

    static func jsonObject(for request: URLRequest) throws -> Any {
        let data = try data(for: request)
        return try JSONSerialization.jsonObject(with: data)
    }

    static func resetTransport() {
        transport = defaultTransport
    }

    private static func defaultTransport(_ request: URLRequest) throws -> (Data, URLResponse) {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<(Data, URLResponse), Error>?
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                result = .failure(error)
            } else if let response {
                result = .success((data ?? Data(), response))
            } else {
                result = .failure(TokenStepError.message(L("网络请求失败")))
            }
            semaphore.signal()
        }
        task.resume()
        if semaphore.wait(timeout: .now() + 8) == .timedOut {
            task.cancel()
            throw TokenStepError.message(L("请求超时"))
        }
        return try result!.get()
    }
}

enum QuotaJSON {
    static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as Double:
            return number
        case let number as Int:
            return Double(number)
        case let number as Int64:
            return Double(number)
        case let text as String:
            return Double(text)
        default:
            return nil
        }
    }

    static func percent(used: Double?, remaining: Double?, total: Double?) -> Double? {
        if let used, used.isFinite {
            if used <= 1 { return min(max(used * 100, 0), 100) }
            if let total, total > 0, used <= total { return min(max(used / total * 100, 0), 100) }
            if used <= 100 { return used }
        }
        if let remaining, let total, total > 0 {
            return min(max((total - remaining) / total * 100, 0), 100)
        }
        return nil
    }
}
