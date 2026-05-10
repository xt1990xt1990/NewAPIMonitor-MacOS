import Foundation

struct BalanceResult {
    let balance: Double      // 剩余额度（美元）
    let used: Double         // 已用额度（美元）
    let total: Double        // 总额度（美元）
    let isUnlimited: Bool    // 是否无限额度
}

struct HubUserStat {
    let name: String
    let costUsd: Double
    let calls: Int
    let tokens: Int
}

struct HubStatsResult {
    let costUsd: Double      // 今日总花费
    let calls: Int           // 总调用次数
    let totalTokens: Int     // 总 Token 数
    let userBreakdown: [HubUserStat]  // 用户明细
}

actor APIService {
    private let session: URLSession
    private let directSession: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)

        let directConfig = URLSessionConfiguration.default
        directConfig.timeoutIntervalForRequest = 15
        directConfig.timeoutIntervalForResource = 30
        directConfig.connectionProxyDictionary = [:]
        self.directSession = URLSession(configuration: directConfig)
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

    /// 获取 Claude Code Hub 用量（通过 leaderboard API）
    func fetchHubStats(hubURL: String, token: String) async throws -> HubStatsResult {
        let base = hubURL.trimmingCharacters(in: .init(charactersIn: "/"))
        let urlString = base + "/api/leaderboard?period=daily&scope=user"
        let url = try makeURL(urlString)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("auth-token=\(token)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let requestSession = shouldBypassProxy(for: url) ? directSession : session
        let (data, response) = try await requestSession.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw APIError.httpError(http.statusCode)
        }

        guard let users = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw APIError.parseError
        }

        var totalCost = 0.0
        var totalCalls = 0
        var totalTokens = 0
        var breakdown: [HubUserStat] = []

        for u in users {
            let cost = toDouble(u["totalCost"]) ?? 0
            let calls = u["totalRequests"] as? Int ?? Int(toDouble(u["totalRequests"]) ?? 0)
            let tokens = u["totalTokens"] as? Int ?? Int(toDouble(u["totalTokens"]) ?? 0)
            let name = u["userName"] as? String ?? "Unknown"

            totalCost += cost
            totalCalls += calls
            totalTokens += tokens
            breakdown.append(HubUserStat(name: name, costUsd: cost, calls: calls, tokens: tokens))
        }

        return HubStatsResult(
            costUsd: totalCost,
            calls: totalCalls,
            totalTokens: totalTokens,
            userBreakdown: breakdown
        )
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

    private func shouldBypassProxy(for url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if host == "localhost" || host.hasSuffix(".local") { return true }
        if host.hasPrefix("10.") || host.hasPrefix("192.168.") { return true }

        let parts = host.split(separator: ".").compactMap { Int($0) }
        if parts.count == 4 {
            if parts[0] == 172 && (16...31).contains(parts[1]) { return true }
            if parts[0] == 127 { return true }
        }

        return false
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
