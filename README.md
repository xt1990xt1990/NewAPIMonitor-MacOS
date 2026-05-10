# APIMonitor for macOS

<div align="center">

![macOS](https://img.shields.io/badge/macOS-11.0+-blue.svg)
![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Version](https://img.shields.io/github/v/release/xt1990xt1990/APIMonitor-MacOS)

一款优雅的 macOS 菜单栏应用，实时监控 NewAPI 服务的 API 消耗情况

[下载最新版本](https://github.com/xt1990xt1990/APIMonitor-MacOS/releases/latest) · [报告问题](https://github.com/xt1990xt1990/APIMonitor-MacOS/issues) · [功能建议](https://github.com/xt1990xt1990/APIMonitor-MacOS/issues)

</div>

---

## ✨ 特性

### 📊 实时监控
- **双站点支持** - 同时监控最多 2 个 NewAPI 站点
- **菜单栏显示** - 实时显示今日消耗或累计消耗
- **自动刷新** - 可自定义刷新间隔（最低 30 秒）
- **智能图标** - 根据站点名称首字母自动生成 SF Symbol 图标

### 📈 数据统计
- **今日消耗** - 自动记录每日 0 点快照，精确计算当日消耗
- **昨日对比** - 显示昨日消耗数据，方便趋势分析
- **累计额度** - 查看 API 已用额度、剩余额度和总额度
- **无限额度支持** - 自动识别无限额度账户

### 🔔 Webhook 日报
- **每日自动推送** - 每天 0 点自动发送消耗报告到 Discord/Slack
- **睡眠唤醒补发** - Mac 睡眠后唤醒自动检查并补发日报
- **去重保护** - 确保每天只发送一次，不会重复推送
- **趋势对比** - 日报包含今日/昨日消耗对比和趋势分析

### 🎨 用户体验
- **原生 SwiftUI** - 完全使用 SwiftUI 构建，性能优异
- **轻量级** - 内存占用低，不影响系统性能
- **开机自启** - 可设置开机自动启动
- **数据持久化** - 使用 @AppStorage 自动保存配置

---

## 📦 安装

### 方式一：下载预编译版本（推荐）

1. 前往 [Releases](https://github.com/xt1990xt1990/APIMonitor-MacOS/releases/latest) 页面
2. 下载最新的 `APIMonitor-MacOS-vX.X.X.zip`
3. 解压并拖动 `APIMonitor.app` 到应用程序文件夹
4. 首次打开时，右键点击应用选择"打开"（绕过 Gatekeeper）

### 方式二：从源码编译

```bash
# 克隆仓库
git clone https://github.com/xt1990xt1990/APIMonitor-MacOS.git
cd APIMonitor-MacOS

# 使用 Xcode 打开项目
open APIMonitor.xcodeproj

# 在 Xcode 中按 Cmd+R 运行
```

**系统要求**
- macOS 11.0 (Big Sur) 或更高版本
- Xcode 15.0+ (仅编译时需要)

---

## 🚀 快速开始

### 1️⃣ 配置站点

首次启动后，点击菜单栏图标 → **设置**：

| 配置项 | 说明 | 示例 |
|--------|------|------|
| **站点名称** | 自定义站点名称 | `OpenAI API` |
| **API 地址** | NewAPI 服务地址 | `https://api.example.com` |
| **访问令牌** | NewAPI 管理员 Token | `sk-xxxxx` |
| **启用站点** | 是否监控此站点 | ✅ |

> 💡 **提示**：站点名称首字母会自动生成菜单栏图标（如 `O` → `o.circle.fill`）

### 2️⃣ 设置刷新间隔

在设置中调整 **刷新间隔**（30-3600 秒），建议：
- 频繁使用：60 秒
- 一般使用：300 秒（5 分钟）
- 低频使用：600 秒（10 分钟）

### 3️⃣ 配置 Webhook（可选）

如需每日自动推送消耗报告：

1. 获取 Discord Webhook URL：
   - 进入 Discord 服务器设置 → 整合 → Webhook
   - 创建新 Webhook 并复制 URL

2. 在应用设置中：
   - 粘贴 Webhook URL
   - 勾选 **启用 Webhook**
   - 点击 **测试连接** 验证

3. 每天 0 点自动发送日报，包含：
   - 今日消耗 / 昨日消耗
   - 消耗趋势（上升/下降/持平）
   - 累计消耗

---

## 📸 截图

### 菜单栏显示
```
🔵 $2.34 ┃ 🟢 $1.56
```

### 设置界面
- 站点配置（名称、URL、Token）
- 刷新间隔设置
- Webhook 配置
- 数据重置

### Webhook 日报示例
```
📈 NewAPI 每日消耗报告
2026年3月23日 星期日

🔹 OpenAI API
今日: $2.34 ｜ 昨日: $1.89
📈 较昨日上升 ｜ 累计: $45.67

🔹 Claude API
今日: $1.56 ｜ 昨日: $1.78
📉 较昨日下降 ｜ 累计: $32.10
```

---

## 🔧 技术架构

### 核心技术栈
- **SwiftUI** - 声明式 UI 框架
- **Combine** - 响应式编程
- **@AppStorage** - 数据持久化
- **URLSession** - 网络请求
- **DispatchSourceTimer** - 精确定时器

### 关键特性实现

#### 午夜快照机制
```swift
// 使用 DispatchSourceTimer (wall clock) 确保睡眠唤醒后触发
let timer = DispatchSource.makeTimerSource(queue: .main)
timer.schedule(wallDeadline: .now() + interval, leeway: .seconds(1))
```

#### 系统唤醒监听
```swift
// 监听 NSWorkspace.didWakeNotification
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didWakeNotification,
    object: nil,
    queue: .main
) { _ in
    // 检查并补发日报
}
```

#### 日报去重
```swift
// 使用 @AppStorage 持久化发送状态
@AppStorage("webhook_report_sent_date") var webhookReportSentDate: String = ""
```

---

## 🛠️ 开发指南

### 项目结构
```
APIMonitor/
├── APIMonitorApp.swift      # 应用入口
├── MonitorState.swift           # 核心状态管理
├── MenuBarView.swift            # 菜单栏视图
├── SettingsView.swift           # 设置界面
├── APIService.swift             # API 请求服务
├── WebhookService.swift         # Webhook 服务
└── SettingsWindowManager.swift  # 设置窗口管理
```

### 构建命令
```bash
# Debug 构建
xcodebuild -scheme APIMonitor -configuration Debug build

# Release 构建
xcodebuild -scheme APIMonitor -configuration Release build

# 打包
cd ~/Library/Developer/Xcode/DerivedData/.../Build/Products/Release
zip -r APIMonitor.zip APIMonitor.app
```

---

## 📝 更新日志

### v1.1.0 (2026-03-23)
#### 🎯 新增功能
- 🕛 使用 DispatchSourceTimer (wall clock) 替代 Combine delay
- 🔔 监听系统唤醒事件，自动检查并补发日报
- 🔒 新增日报去重机制，防止重复发送

#### 🐛 问题修复
- 修复 Mac 睡眠导致午夜快照轮转不触发的问题
- 修复 Mac 睡眠导致 Webhook 日报不发送的问题

#### 🔧 技术改进
- 三层保障机制确保日报可靠发送
- 使用 @AppStorage 持久化发送状态
- 正确清理定时器和通知观察者

### v0.1.0 (2026-03-19)
- 🎉 首次发布
- 支持双站点监控
- 实时菜单栏显示
- Webhook 日报推送

[查看完整更新日志](https://github.com/xt1990xt1990/APIMonitor-MacOS/releases)

---

## ❓ 常见问题

### Q: 为什么菜单栏不显示数据？
**A:** 请检查：
1. 站点是否已启用
2. API 地址和 Token 是否正确
3. 网络连接是否正常
4. 查看设置中的错误提示

### Q: Webhook 日报没有收到？
**A:** 可能原因：
1. Mac 在午夜时处于睡眠状态 → v1.1.0 已修复，唤醒后会自动补发
2. Webhook URL 配置错误 → 使用"测试连接"验证
3. Discord/Slack 服务异常 → 检查服务状态

### Q: 如何重置所有数据？
**A:** 在设置界面点击 **重置所有数据** 按钮，将清除：
- 所有快照数据
- 今日/昨日消耗记录
- Webhook 发送状态

### Q: 支持哪些 Webhook 服务？
**A:** 目前支持所有兼容 Discord Webhook 格式的服务：
- Discord
- Slack (需使用 Discord 兼容模式)
- 其他支持 Embed 格式的服务

---

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

### 贡献指南
1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启 Pull Request

### 开发规范
- 遵循 Swift 官方代码风格
- 使用有意义的提交信息
- 添加必要的注释和文档
- 确保代码通过编译

---

## 📄 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件

---

## 🙏 致谢

- [NewAPI](https://github.com/Calcium-Ion/new-api) - 优秀的 API 管理系统
- [SwiftUI](https://developer.apple.com/xcode/swiftui/) - 强大的 UI 框架
- 所有贡献者和用户的支持

---

## 📮 联系方式

- **Issues**: [GitHub Issues](https://github.com/xt1990xt1990/APIMonitor-MacOS/issues)
- **Discussions**: [GitHub Discussions](https://github.com/xt1990xt1990/APIMonitor-MacOS/discussions)

---

<div align="center">

**如果这个项目对你有帮助，请给个 ⭐️ Star 支持一下！**

Made with ❤️ by [xt1990xt1990](https://github.com/xt1990xt1990)

</div>
