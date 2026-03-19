import Foundation

struct BalanceResult {
    let balance: Double      // 剩余额度（美元）
    let used: Double         // 已用额度（美元）
    let total: Double        // 总额度（美元）
    let isUnlimited: Bool    // 是否无限额度
}

actor APIService {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    /// 获取余额信息
    func fetchBalance(baseURL: String, token: String) async throws -> BalanceResult {
        let base = baseURL.trimmingCharacters(in: .init(charactersIn: "/"))

        // 1. 获取总额度
        let subURL = try makeURL(base + "/v1/dashboard/billing/subscription")
        let subData = try await get(url: subURL, token: token)

        guard let subJSON = try? JSONSerialization.jsonObject(with: subData) as? [String: Any],
              let hardLimit = toDouble(subJSON["hard_limit_usd"]) else {
            throw APIError.parseError
        }

        let isUnlimited = hardLimit >= 100_000_000

        // 2. 获取已用额度
        let used = try await fetchUsage(baseURL: base, token: token)

        if isUnlimited {
            return BalanceResult(balance: 0, used: used, total: hardLimit, isUnlimited: true)
        }

        let remaining = hardLimit - used
        return BalanceResult(balance: remaining, used: used, total: hardLimit, isUnlimited: false)
    }

    private func fetchUsage(baseURL: String, token: String) async throws -> Double {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        let start = formatter.string(from: Calendar.current.date(byAdding: .day, value: -90, to: Date())!)

        let url = try makeURL(baseURL + "/v1/dashboard/billing/usage?start_date=\(start)&end_date=\(today)")
        let data = try await get(url: url, token: token)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let totalUsage = toDouble(json["total_usage"]) else {
            throw APIError.parseError
        }
        // total_usage 单位是 0.01 美分，÷100 换算成美元
        return totalUsage / 100.0
    }

    // MARK: - 工具方法

    private func get(url: URL, token: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw APIError.httpError(http.statusCode)
        }
        return data
    }

    private func makeURL(_ string: String) throws -> URL {
        guard let url = URL(string: string) else { throw APIError.invalidURL }
        return url
    }

    private func toDouble(_ value: Any?) -> Double? {
        switch value {
        case let n as Double: return n
        case let n as Int: return Double(n)
        case let n as Int64: return Double(n)
        case let s as String: return Double(s)
        default: return nil
        }
    }
}

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case parseError

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的 URL"
        case .invalidResponse: return "无效的响应"
        case .httpError(let code): return "HTTP 错误 \(code)"
        case .parseError: return "数据解析失败，请检查 API 地址和 Token"
        }
    }
}
