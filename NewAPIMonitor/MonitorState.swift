import SwiftUI
import SwiftUI
import Combine
import AppKit

@MainActor
class MonitorState: ObservableObject {
    // MARK: - 站点配置
    @AppStorage("site1_name") var site1Name = "站点 1"
    @AppStorage("site1_url") var site1URL = ""
    @AppStorage("site1_token") var site1Token = ""
    @AppStorage("site1_enabled") var site1Enabled = true
    @AppStorage("site1_logo") var site1Logo = ""

    @AppStorage("site2_name") var site2Name = "站点 2"
    @AppStorage("site2_url") var site2URL = ""
    @AppStorage("site2_token") var site2Token = ""
    @AppStorage("site2_enabled") var site2Enabled = false
    @AppStorage("site2_logo") var site2Logo = ""

    // MARK: - 通用设置
    @AppStorage("refreshInterval") var refreshInterval: Double = 60
    @AppStorage("displayMode") var displayMode: DisplayMode = .today
    @AppStorage("webhookURL") var webhookURL = ""
    @AppStorage("webhookEnabled") var webhookEnabled = false

    // MARK: - 每日快照（持久化）
    // 快照记录的是当日0点（或首次启动）时的 API 已用额度
    @AppStorage("snap_date") var snapDate: String = ""
    @AppStorage("snap_time") var snapTime: String = ""
    @AppStorage("snap_site1_used") var snapSite1Used: Double = 0
    @AppStorage("snap_site2_used") var snapSite2Used: Double = 0
    // 昨日快照（用于计算昨日消耗）
    @AppStorage("snap_yesterday_site1_used") var snapYesterdaySite1Used: Double = 0
    @AppStorage("snap_yesterday_site2_used") var snapYesterdaySite2Used: Double = 0
    @AppStorage("snap_yesterday_date") var snapYesterdayDate: String = ""
    // 前日快照（用于日报中"昨日"对比）
    @AppStorage("snap_day_before_yesterday_site1_used") var snapDayBeforeYesterdaySite1Used: Double = 0
    @AppStorage("snap_day_before_yesterday_site2_used") var snapDayBeforeYesterdaySite2Used: Double = 0
    // Webhook 日报已发送标记（记录已发送日报的日期，防止重复发送）
    @AppStorage("webhook_report_sent_date") var webhookReportSentDate: String = ""
    // MARK: - 运行时状态
    @Published var site1Balance: Double = 0
    @Published var site1Used: Double = 0
    @Published var site1Total: Double = 0
    @Published var site1Unlimited = false
    @Published var site1UsedToday: Double = 0

    @Published var site2Balance: Double = 0
    @Published var site2Used: Double = 0
    @Published var site2Total: Double = 0
    @Published var site2Unlimited = false
    @Published var site2UsedToday: Double = 0

    @Published var lastRefresh: Date?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var refreshTimer: AnyCancellable?
    private var midnightTimer: DispatchSourceTimer?
    private var wakeObserver: NSObjectProtocol?
    private let api = APIService()
    private let webhook = WebhookService()

    private var todayString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    // MARK: - 菜单栏图标和数值

    /// 从站点名首字母生成 SF Symbol 名称
    private func letterIcon(for name: String) -> String {
        if let first = name.lowercased().first, first.isLetter, first.isASCII {
            return "\(first).circle.fill"
        }
        return "server.rack"
    }

    var site1IconName: String { letterIcon(for: site1Name) }
    var site2IconName: String { letterIcon(for: site2Name) }

    var site1DisplayValue: String {
        switch displayMode {
        case .today: return String(format: "$%.2f", site1UsedToday)
        case .cumulative: return String(format: "$%.2f", site1Used)
        }
    }

    var site2DisplayValue: String {
        switch displayMode {
        case .today: return String(format: "$%.2f", site2UsedToday)
        case .cumulative: return String(format: "$%.2f", site2Used)
        }
    }

    struct MenuBarPart: Identifiable {
        let id = UUID()
        let value: String
        let isIcon: Bool
    }

    var menuBarLabelParts: [MenuBarPart] {
        var parts: [MenuBarPart] = []
        if site1Enabled {
            parts.append(MenuBarPart(value: site1IconName, isIcon: true))
            parts.append(MenuBarPart(value: site1DisplayValue, isIcon: false))
        }
        if site1Enabled && site2Enabled {
            parts.append(MenuBarPart(value: " ┃ ", isIcon: false))
        }
        if site2Enabled {
            parts.append(MenuBarPart(value: site2IconName, isIcon: true))
            parts.append(MenuBarPart(value: site2DisplayValue, isIcon: false))
        }
        return parts
    }

    var menuBarText: String {
        var segments: [String] = []
        if site1Enabled {
            let initial = site1Name.prefix(1).uppercased()
            segments.append("\(initial) \(site1DisplayValue)")
        }
        if site2Enabled {
            let initial = site2Name.prefix(1).uppercased()
            segments.append("\(initial) \(site2DisplayValue)")
        }
        return segments.joined(separator: " ┃ ")
    }

    /// 昨日消耗
    var site1YesterdayDelta: Double {
        guard !snapYesterdayDate.isEmpty else { return 0 }
        return max(0, snapSite1Used - snapYesterdaySite1Used)
    }

    var site2YesterdayDelta: Double {
        guard !snapYesterdayDate.isEmpty else { return 0 }
        return max(0, snapSite2Used - snapYesterdaySite2Used)
    }

    /// 前日消耗（日报中用作"昨日"对比）
    var site1DayBeforeYesterdayDelta: Double {
        guard snapDayBeforeYesterdaySite1Used > 0 else { return 0 }
        return max(0, snapYesterdaySite1Used - snapDayBeforeYesterdaySite1Used)
    }

    var site2DayBeforeYesterdayDelta: Double {
        guard snapDayBeforeYesterdaySite2Used > 0 else { return 0 }
        return max(0, snapYesterdaySite2Used - snapDayBeforeYesterdaySite2Used)
    }

    init() {
        startRefreshTimer()
        scheduleMidnightSnapshot()
        observeSystemWake()
        Task { await refresh() }
    }

    deinit {
        midnightTimer?.cancel()
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    // MARK: - 快照逻辑

    /// 检查是否需要做今日快照（每日首次启动或跨天）
    /// 必须在拿到 API 数据后调用
    private func ensureTodaySnapshot(site1Used: Double, site2Used: Double) {
        let today = todayString
        if snapDate == today {
            // 今天已经快照过，不需要再做
            return
        }

        // 把"昨日"挪到"前日"，再把当前快照挪到"昨日"
        if !snapDate.isEmpty {
            snapDayBeforeYesterdaySite1Used = snapYesterdaySite1Used
            snapDayBeforeYesterdaySite2Used = snapYesterdaySite2Used
            snapYesterdaySite1Used = snapSite1Used
            snapYesterdaySite2Used = snapSite2Used
            snapYesterdayDate = snapDate
        }

        // 记录今日快照 = 当前 API 已用额度
        snapSite1Used = site1Used
        snapSite2Used = site2Used
        snapDate = today
        let tf = DateFormatter()
        tf.dateFormat = "HH:mm:ss"
        snapTime = tf.string(from: Date())
    }

    // MARK: - 刷新逻辑

    func refresh() async {
        isLoading = true
        errorMessage = nil

        async let r1: Void = refreshSite1()
        async let r2: Void = refreshSite2()
        _ = await (r1, r2)

        // 拿到数据后检查快照
        ensureTodaySnapshot(site1Used: site1Used, site2Used: site2Used)

        // 计算今日消耗 = 当前已用 - 今日快照已用
        site1UsedToday = max(0, site1Used - snapSite1Used)
        site2UsedToday = max(0, site2Used - snapSite2Used)

        lastRefresh = Date()
        isLoading = false
    }

    private func refreshSite1() async {
        guard site1Enabled, !site1URL.isEmpty, !site1Token.isEmpty else { return }
        do {
            let result = try await api.fetchBalance(baseURL: site1URL, token: site1Token)
            site1Balance = result.balance
            site1Used = result.used
            site1Total = result.total
            site1Unlimited = result.isUnlimited
        } catch {
            errorMessage = "站点1: \(error.localizedDescription)"
        }
    }

    private func refreshSite2() async {
        guard site2Enabled, !site2URL.isEmpty, !site2Token.isEmpty else { return }
        do {
            let result = try await api.fetchBalance(baseURL: site2URL, token: site2Token)
            site2Balance = result.balance
            site2Used = result.used
            site2Total = result.total
            site2Unlimited = result.isUnlimited
        } catch {
            errorMessage = (errorMessage ?? "") + " 站点2: \(error.localizedDescription)"
        }
    }

    // MARK: - 定时器

    func startRefreshTimer() {
        refreshTimer?.cancel()
        let interval = max(30, refreshInterval)
        refreshTimer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.refresh() }
            }
    }

    private func scheduleMidnightSnapshot() {
        midnightTimer?.cancel()

        let now = Date()
        let calendar = Calendar.current
        guard let nextMidnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return }
        let interval = nextMidnight.timeIntervalSince(now)

        // 使用 DispatchSourceTimer —— 基于挂钟时间（wall clock），即使系统睡眠也能在唤醒后立即触发
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(wallDeadline: .now() + interval, leeway: .seconds(1))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.handleMidnightTrigger()
            }
        }
        timer.resume()
        midnightTimer = timer
    }

    /// 系统从睡眠唤醒时检查是否错过了午夜触发
    private func observeSystemWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.checkAndSendDailyReport()
                // 唤醒后重新校准午夜定时器
                self.scheduleMidnightSnapshot()
            }
        }
    }

    /// 午夜定时器触发时执行
    private func handleMidnightTrigger() async {
        await refresh() // 刷新数据，自动触发快照轮转
        await checkAndSendDailyReport()
        scheduleMidnightSnapshot() // 安排下一个午夜
    }

    /// 检查今天是否已发送日报，若未发送则发送
    private func checkAndSendDailyReport() async {
        let today = todayString
        guard webhookEnabled, !webhookURL.isEmpty else { return }
        guard webhookReportSentDate != today else { return } // 今天已发送，跳过

        // 先确保数据是最新的
        if lastRefresh == nil || Date().timeIntervalSince(lastRefresh!) > 60 {
            await refresh()
        }
        await sendDailyReport()
        webhookReportSentDate = today
    }

    // MARK: - Webhook

    func sendDailyReport() async {
        // 日报在午夜后发送，快照已轮转：
        // yesterdayDelta = 刚结束的一天消耗（报告中显示为"今日"）
        // dayBeforeYesterdayDelta = 前天消耗（报告中显示为"昨日"，用于对比）
        let payload = webhook.buildDailyReport(
            site1Name: site1Name,
            site1Enabled: site1Enabled,
            site1TodayUsed: site1YesterdayDelta,
            site1YesterdayUsed: site1DayBeforeYesterdayDelta,
            site1Cumulative: site1Used,
            site2Name: site2Name,
            site2Enabled: site2Enabled,
            site2TodayUsed: site2YesterdayDelta,
            site2YesterdayUsed: site2DayBeforeYesterdayDelta,
            site2Cumulative: site2Used
        )
        let success = await webhook.send(payload: payload, to: webhookURL)
        if !success {
            errorMessage = "Webhook 日报发送失败"
        }
    }

    // MARK: - 重置

    func resetAllData() {
        snapDate = ""
        snapTime = ""
        snapSite1Used = 0
        snapSite2Used = 0
        snapYesterdayDate = ""
        snapYesterdaySite1Used = 0
        snapYesterdaySite2Used = 0
        snapDayBeforeYesterdaySite1Used = 0
        snapDayBeforeYesterdaySite2Used = 0
        site1UsedToday = 0
        site2UsedToday = 0
        webhookReportSentDate = ""
    }
}

// MARK: - DisplayMode

enum DisplayMode: String, CaseIterable {
    case today = "today"
    case cumulative = "cumulative"

    var label: String {
        switch self {
        case .today: return "今日消耗"
        case .cumulative: return "累计消耗"
        }
    }
}
