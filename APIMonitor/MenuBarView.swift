import SwiftUI

struct MenuBarView: View {
    @ObservedObject var state: MonitorState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.accentColor)
                Text("APIMonitor")
                    .font(.headline)
                Spacer()
                if state.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            Divider()

            // 站点 1
            if state.site1Enabled {
                SiteStatusView(
                    name: state.site1Name,
                    balance: state.site1Balance,
                    used: state.site1Used,
                    total: state.site1Total,
                    isUnlimited: state.site1Unlimited,
                    todayUsed: state.site1UsedToday,
                    yesterdayUsed: state.site1YesterdayDelta,
                    cumulative: state.site1Used
                )
            }

            // 站点 2
            if state.site2Enabled {
                SiteStatusView(
                    name: state.site2Name,
                    balance: state.site2Balance,
                    used: state.site2Used,
                    total: state.site2Total,
                    isUnlimited: state.site2Unlimited,
                    todayUsed: state.site2UsedToday,
                    yesterdayUsed: state.site2YesterdayDelta,
                    cumulative: state.site2Used
                )
            }

            // Claude Code Hub
            if state.hubEnabled {
                HubStatusView(
                    costToday: state.hubCostToday,
                    calls: state.hubCalls,
                    totalTokens: state.hubTotalTokens,
                    userBreakdown: state.hubUserBreakdown,
                    yesterdayCost: state.hubYesterdayDelta
                )
            }

            Divider()

            // 错误信息
            if let error = state.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }

            // 底部操作
            HStack {
                if let last = state.lastRefresh {
                    Text("更新于 \(last.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("刷新") {
                    Task { await state.refresh() }
                }
                .buttonStyle(.borderless)
            }

            HStack {
                Button(action: {
                    SettingsWindowManager.shared.open(state: state)
                }) {
                    Text("设置")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.1))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Spacer()

                Button("退出") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .foregroundColor(.red)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}

// MARK: - 单站点状态卡片

struct SiteStatusView: View {
    let name: String
    let balance: Double
    let used: Double
    let total: Double
    let isUnlimited: Bool
    let todayUsed: Double
    let yesterdayUsed: Double
    let cumulative: Double

    private var trend: String {
        if todayUsed > yesterdayUsed { return "↑" }
        if todayUsed < yesterdayUsed { return "↓" }
        return "→"
    }

    private var trendColor: Color {
        if todayUsed > yesterdayUsed { return .red }
        if todayUsed < yesterdayUsed { return .green }
        return .secondary
    }

    private var balanceText: String {
        isUnlimited ? "无限" : String(format: "$%.2f", balance)
    }

    private var totalText: String {
        isUnlimited ? "无限" : String(format: "$%.2f", total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(.subheadline)
                .fontWeight(.medium)

            // 余额 / 已用 / 总额
            HStack {
                Label {
                    Text(balanceText)
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "creditcard")
                        .foregroundColor(.secondary)
                }
                .font(.caption)
                .help("剩余额度")

                Spacer()

                Text(String(format: "$%.2f / %@", used, totalText))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    .help("已用 / 总额")
            }

            // 今日 / 昨日 / 累计
            HStack {
                Text("今日")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Text(String(format: "$%.2f", todayUsed))
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.semibold)

                Text(trend)
                    .foregroundColor(trendColor)
                    .font(.caption)

                Text(String(format: "昨日 $%.2f", yesterdayUsed))
                    .foregroundColor(.secondary)
                    .font(.caption2)

                Spacer()

                Label {
                    Text(String(format: "$%.2f", cumulative))
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "sum")
                        .foregroundColor(.secondary)
                }
                .font(.caption)
                .help("累计消耗")
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Hub 状态卡片

struct HubStatusView: View {
    let costToday: Double
    let calls: Int
    let totalTokens: Int
    let userBreakdown: [HubUserStat]
    let yesterdayCost: Double

    private var trend: String {
        if costToday > yesterdayCost { return "↑" }
        if costToday < yesterdayCost { return "↓" }
        return "→"
    }

    private var trendColor: Color {
        if costToday > yesterdayCost { return .red }
        if costToday < yesterdayCost { return .green }
        return .secondary
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Claude Code Hub")
                .font(.subheadline)
                .fontWeight(.medium)

            // 今日花费 + 调用次数 + Token
            HStack {
                Label {
                    Text(String(format: "$%.2f", costToday))
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "dollarsign.circle")
                        .foregroundColor(.secondary)
                }
                .font(.caption)
                .help("今日花费")

                Spacer()

                Text("\(calls) 次")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    .help("调用次数")

                Text("·")
                    .foregroundColor(.secondary)
                    .font(.caption)

                Text(formatTokens(totalTokens))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    .help("Token")
            }

            // 趋势
            HStack {
                Text("今日")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Text(String(format: "$%.2f", costToday))
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.semibold)

                Text(trend)
                    .foregroundColor(trendColor)
                    .font(.caption)

                Text(String(format: "昨日 $%.2f", yesterdayCost))
                    .foregroundColor(.secondary)
                    .font(.caption2)

                Spacer()
            }

            // 用户明细
            if !userBreakdown.isEmpty {
                Divider().opacity(0.5)
                ForEach(userBreakdown, id: \.name) { user in
                    HStack {
                        Text(user.name)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text(String(format: "$%.2f", user.costUsd))
                            .font(.system(.caption2, design: .monospaced))
                        Text("(\(user.calls) 次)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}
