import SwiftUI
import ServiceManagement

// MARK: - 通用卡片容器

struct SettingsCard<Content: View>: View {
    let icon: String
    let title: String
    var accent: Color = .accentColor
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(title).font(.system(size: 13, weight: .semibold))
            } icon: {
                Image(systemName: icon)
                    .foregroundColor(accent)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
        }
        .padding(14)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(accent == .red ? Color.red.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    }
}

// MARK: - 统一输入行

struct SettingsTextField: View {
    let label: String
    @Binding var text: String
    var isSecure: Bool = false
    var isURL: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .frame(width: 72, alignment: .leading)
            if isSecure {
                SecureField("", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            } else {
                TextField("", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(isURL ? .URL : .none)
                    .font(.system(size: 12, design: isURL ? .monospaced : .default))
            }
        }
    }
}

// MARK: - 主设置窗口

struct SettingsView: View {
    @ObservedObject var state: MonitorState
    @State private var testingWebhook = false
    @State private var webhookTestResult: String?

    var body: some View {
        TabView {
            SitesSettingsTab(state: state)
                .tabItem { Label("站点", systemImage: "server.rack") }
            GeneralSettingsTab(state: state)
                .tabItem { Label("通用", systemImage: "gear") }
            WebhookSettingsTab(
                state: state,
                testingWebhook: $testingWebhook,
                webhookTestResult: $webhookTestResult
            )
            .tabItem { Label("Webhook", systemImage: "bell") }
            DataSettingsTab(state: state)
                .tabItem { Label("数据", systemImage: "cylinder.split.1x2") }
        }
        .frame(width: 480, height: 520)
    }
}

// MARK: - 站点设置

struct SitesSettingsTab: View {
    @ObservedObject var state: MonitorState
    @State private var applyStatus: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                siteCard(
                    icon: "1.circle.fill", title: "站点 1",
                    enabled: $state.site1Enabled, name: $state.site1Name,
                    url: $state.site1URL, token: $state.site1Token
                )
                siteCard(
                    icon: "2.circle.fill", title: "站点 2",
                    enabled: $state.site2Enabled, name: $state.site2Name,
                    url: $state.site2URL, token: $state.site2Token
                )

                // Claude Code Hub
                SettingsCard(icon: "cpu.fill", title: "Claude Code Hub") {
                    Toggle("启用", isOn: $state.hubEnabled).font(.system(size: 13))
                    Divider().opacity(0.5)
                    SettingsTextField(label: "Hub 地址", text: $state.hubURL, isURL: true)
                    SettingsTextField(label: "Token", text: $state.hubToken, isSecure: true)
                }
                .opacity(state.hubEnabled ? 1 : 0.55)

                HStack {
                    Button(action: {
                        applyStatus = nil
                        Task {
                            await state.refresh()
                            applyStatus = state.errorMessage.map { "⚠️ \($0)" } ?? "✅ 已刷新"
                        }
                    }) {
                        Label("应用并刷新", systemImage: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    if let status = applyStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundColor(status.hasPrefix("✅") ? .green : .orange)
                    }
                    Spacer()
                }
                .padding(.horizontal, 2)
            }
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func siteCard(
        icon: String, title: String,
        enabled: Binding<Bool>, name: Binding<String>,
        url: Binding<String>, token: Binding<String>
    ) -> some View {
        SettingsCard(icon: icon, title: title) {
            Toggle("启用", isOn: enabled).font(.system(size: 13))
            Divider().opacity(0.5)
            SettingsTextField(label: "名称", text: name)
            SettingsTextField(label: "API 地址", text: url, isURL: true)
            SettingsTextField(label: "API Token", text: token, isSecure: true)
        }
        .opacity(enabled.wrappedValue ? 1 : 0.55)
    }
}

// MARK: - 通用设置

struct GeneralSettingsTab: View {
    @ObservedObject var state: MonitorState
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SettingsCard(icon: "eye", title: "显示") {
                    HStack {
                        Text("菜单栏显示")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("", selection: $state.displayMode) {
                            Text("今日消耗").tag(DisplayMode.today)
                            Text("累计消耗").tag(DisplayMode.cumulative)
                        }
                        .labelsHidden()
                        .frame(width: 130)
                    }

                    Divider().opacity(0.5)

                    HStack {
                        Text("刷新间隔")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        Slider(value: $state.refreshInterval, in: 30...300, step: 10)
                        Text("\(Int(state.refreshInterval))秒")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.primary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }

                SettingsCard(icon: "laptopcomputer", title: "系统") {
                    Toggle("开机自启", isOn: $launchAtLogin)
                        .font(.system(size: 13))
                        .onChange(of: launchAtLogin) { _, newValue in
                            do {
                                if newValue {
                                    try SMAppService.mainApp.register()
                                } else {
                                    try SMAppService.mainApp.unregister()
                                }
                            } catch {
                                launchAtLogin = SMAppService.mainApp.status == .enabled
                            }
                        }
                }
            }
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: state.refreshInterval) {
            state.startRefreshTimer()
        }
    }
}

// MARK: - Webhook 设置

struct WebhookSettingsTab: View {
    @ObservedObject var state: MonitorState
    @Binding var testingWebhook: Bool
    @Binding var webhookTestResult: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SettingsCard(icon: "paperplane", title: "Discord Webhook") {
                    Toggle("启用每日推送", isOn: $state.webhookEnabled)
                        .font(.system(size: 13))

                    Divider().opacity(0.5)

                    SettingsTextField(label: "URL", text: $state.webhookURL, isURL: true)

                    HStack(spacing: 8) {
                        Button(action: {
                            Task {
                                testingWebhook = true
                                webhookTestResult = nil
                                let success = await WebhookService().sendTest(url: state.webhookURL)
                                webhookTestResult = success ? "✅ 发送成功" : "❌ 发送失败"
                                testingWebhook = false
                            }
                        }) {
                            Label("发送测试", systemImage: "paperplane")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(state.webhookURL.isEmpty || testingWebhook)

                        if testingWebhook {
                            ProgressView().scaleEffect(0.7)
                        }
                        if let result = webhookTestResult {
                            Text(result).font(.caption)
                        }
                        Spacer()
                    }
                }

                SettingsCard(icon: "info.circle", title: "说明", accent: .secondary) {
                    Text("每日 0:00 自动发送消耗日报到 Discord\n日报包含：今日消耗、昨日对比、累计消耗")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineSpacing(3)
                }
            }
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - 数据设置

struct DataSettingsTab: View {
    @ObservedObject var state: MonitorState
    @State private var showResetAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SettingsCard(icon: "chart.bar", title: "累计数据") {
                    HStack {
                        Text("站点 1 累计")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "$%.2f", state.site1Used))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                    }
                    Divider().opacity(0.5)
                    HStack {
                        Text("站点 2 累计")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "$%.2f", state.site2Used))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                    }
                    if state.hubEnabled {
                        Divider().opacity(0.5)
                        HStack {
                            Text("Hub 今日花费")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "$%.2f", state.hubCostToday))
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                        }
                    }
                    Divider().opacity(0.5)
                    HStack {
                        Text("上次快照")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(state.snapDate.isEmpty ? "暂无" : "\(state.snapDate) \(state.snapTime)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }

                SettingsCard(icon: "exclamationmark.triangle", title: "危险操作", accent: .red) {
                    Button(role: .destructive) {
                        showResetAlert = true
                    } label: {
                        Label("重置所有累计数据", systemImage: "trash")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("确认重置", isPresented: $showResetAlert) {
            Button("取消", role: .cancel) {}
            Button("重置", role: .destructive) {
                state.resetAllData()
            }
        } message: {
            Text("将清除所有累计消耗数据和快照记录，此操作不可撤销。")
        }
    }
}
