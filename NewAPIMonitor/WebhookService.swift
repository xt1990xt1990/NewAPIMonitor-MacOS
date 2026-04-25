import Foundation

struct WebhookService {
    struct SendResult {
        let success: Bool
        let message: String?
    }

    struct DiscordEmbed: Codable {
        let title: String?
        let description: String?
        let color: Int?
        let fields: [Field]?
        let footer: Footer?
        let timestamp: String?

        struct Field: Codable {
            let name: String
            let value: String
            let inline: Bool?
        }

        struct Footer: Codable {
            let text: String
        }
    }

    struct DiscordPayload: Codable {
        let content: String?
        let embeds: [DiscordEmbed]?
    }

    // MARK: - 日报生成

    func buildDailyReport(
        site1Name: String,
        site1Enabled: Bool,
        site1TodayUsed: Double,
        site1YesterdayUsed: Double,
        site1Cumulative: Double,
        site2Name: String,
        site2Enabled: Bool,
        site2TodayUsed: Double,
        site2YesterdayUsed: Double,
        site2Cumulative: Double,
        hubEnabled: Bool = false,
        hubTodayCost: Double = 0,
        hubYesterdayCost: Double = 0,
        hubCalls: Int = 0,
        hubTotalTokens: Int = 0
    ) -> DiscordPayload {
        var fields: [DiscordEmbed.Field] = []

        if site1Enabled {
            fields.append(contentsOf: buildSiteFields(
                name: site1Name,
                todayUsed: site1TodayUsed,
                yesterdayUsed: site1YesterdayUsed,
                cumulative: site1Cumulative
            ))
        }

        if site2Enabled {
            fields.append(contentsOf: buildSiteFields(
                name: site2Name,
                todayUsed: site2TodayUsed,
                yesterdayUsed: site2YesterdayUsed,
                cumulative: site2Cumulative
            ))
        }

        if hubEnabled {
            fields.append(contentsOf: buildHubFields(
                todayCost: hubTodayCost,
                yesterdayCost: hubYesterdayCost,
                calls: hubCalls,
                totalTokens: hubTotalTokens
            ))
        }

        let embed = DiscordEmbed(
            title: "📈 NewAPI 每日消耗报告",
            description: formatDate(Date()),
            color: 0x5865F2, // Discord blurple
            fields: fields,
            footer: DiscordEmbed.Footer(text: "NewAPI Monitor for macOS"),
            timestamp: ISO8601DateFormatter().string(from: Date())
        )

        return DiscordPayload(content: nil, embeds: [embed])
    }

    private func buildSiteFields(
        name: String,
        todayUsed: Double,
        yesterdayUsed: Double,
        cumulative: Double
    ) -> [DiscordEmbed.Field] {
        let trend: String
        if todayUsed > yesterdayUsed {
            trend = "📈 较昨日上升"
        } else if todayUsed < yesterdayUsed {
            trend = "📉 较昨日下降"
        } else {
            trend = "➡️ 与昨日持平"
        }

        return [
            DiscordEmbed.Field(
                name: "🔹 \(name)",
                value: String(format: "今日: $%.2f ｜ 昨日: $%.2f\n%@ ｜ 累计: $%.2f",
                              todayUsed, yesterdayUsed, trend, cumulative),
                inline: false
            )
        ]
    }

    private func buildHubFields(
        todayCost: Double,
        yesterdayCost: Double,
        calls: Int,
        totalTokens: Int
    ) -> [DiscordEmbed.Field] {
        let trend: String
        if todayCost > yesterdayCost {
            trend = "📈 较昨日上升"
        } else if todayCost < yesterdayCost {
            trend = "📉 较昨日下降"
        } else {
            trend = "➡️ 与昨日持平"
        }

        let fmtTokens: String
        if totalTokens >= 1_000_000 {
            fmtTokens = String(format: "%.1fM", Double(totalTokens) / 1_000_000)
        } else if totalTokens >= 1_000 {
            fmtTokens = String(format: "%.1fk", Double(totalTokens) / 1_000)
        } else {
            fmtTokens = "\(totalTokens)"
        }

        return [
            DiscordEmbed.Field(
                name: "🤖 Claude Code Hub",
                value: String(format: "今日: $%.2f ｜ 昨日: $%.2f\n%@ ｜ 调用: %d 次 ｜ Token: %@",
                              todayCost, yesterdayCost, trend, calls, fmtTokens),
                inline: false
            )
        ]
    }

    // MARK: - 发送

    func send(payload: DiscordPayload, to webhookURL: String) async -> Bool {
        let result = await sendWithResult(payload: payload, to: webhookURL)
        return result.success
    }

    func sendWithResult(payload: DiscordPayload, to webhookURL: String) async -> SendResult {
        guard let url = URL(string: webhookURL) else {
            return SendResult(success: false, message: "Webhook URL 无效")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        guard let body = try? JSONEncoder().encode(payload) else {
            return SendResult(success: false, message: "Webhook 内容编码失败")
        }
        request.httpBody = body

        let primaryResult = await send(request: request, session: .shared)
        if primaryResult.success {
            return primaryResult
        }

        let directConfig = URLSessionConfiguration.default
        directConfig.timeoutIntervalForRequest = 15
        directConfig.timeoutIntervalForResource = 30
        directConfig.connectionProxyDictionary = [:]
        let directSession = URLSession(configuration: directConfig)
        let directResult = await send(request: request, session: directSession)
        return directResult.success ? directResult : primaryResult
    }

    private func send(request: URLRequest, session: URLSession) async -> SendResult {
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                if (200...299).contains(http.statusCode) {
                    return SendResult(success: true, message: nil)
                }
                let responseBody = String(data: data, encoding: .utf8)
                return SendResult(success: false, message: responseBody ?? "HTTP 错误 \(http.statusCode)")
            }
            return SendResult(success: false, message: "Webhook 响应无效")
        } catch {
            return SendResult(success: false, message: error.localizedDescription)
        }
    }

    func sendTest(url: String) async -> Bool {
        let payload = DiscordPayload(
            content: nil,
            embeds: [
                DiscordEmbed(
                    title: "🧪 测试消息",
                    description: "NewAPI Monitor for macOS 连接测试成功！",
                    color: 0x57F287, // green
                    fields: nil,
                    footer: DiscordEmbed.Footer(text: "NewAPI Monitor"),
                    timestamp: ISO8601DateFormatter().string(from: Date())
                )
            ]
        )
        return await send(payload: payload, to: url)
    }

    func sendTestWithResult(url: String) async -> SendResult {
        let payload = DiscordPayload(
            content: nil,
            embeds: [
                DiscordEmbed(
                    title: "🧪 测试消息",
                    description: "NewAPI Monitor for macOS 连接测试成功！",
                    color: 0x57F287, // green
                    fields: nil,
                    footer: DiscordEmbed.Footer(text: "NewAPI Monitor"),
                    timestamp: ISO8601DateFormatter().string(from: Date())
                )
            ]
        )
        return await sendWithResult(payload: payload, to: url)
    }

    // MARK: - 工具

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 EEEE"
        return formatter.string(from: date)
    }
}
