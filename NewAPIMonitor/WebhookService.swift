import Foundation

struct WebhookService {

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
        site2Cumulative: Double
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

    // MARK: - 发送

    func send(payload: DiscordPayload, to webhookURL: String) async -> Bool {
        guard let url = URL(string: webhookURL) else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        guard let body = try? JSONEncoder().encode(payload) else { return false }
        request.httpBody = body

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                return (200...299).contains(http.statusCode)
            }
            return false
        } catch {
            return false
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

    // MARK: - 工具

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 EEEE"
        return formatter.string(from: date)
    }
}
