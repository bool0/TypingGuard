// Copyright 2026 The TypingGuard Authors
// SPDX-License-Identifier: Apache-2.0

// TypingGuard — 打字时自动屏蔽触控板误触（类似笔记本的防误触）
// 原理：监听键盘按键；按键后 N 毫秒内，吞掉点击 / 拖动 / 滚动（可选：光标移动）。
// 需要「辅助功能」权限。

import Cocoa
import ApplicationServices
import ServiceManagement
import SwiftUI
import Combine

// MARK: - 核心拦截逻辑

final class Guard: ObservableObject {
    static let defaultWindowMs = 500.0

    @Published var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: "enabled") } }
    /// 按键后屏蔽触控板的时长（毫秒）
    @Published var windowMs: Double { didSet { UserDefaults.standard.set(windowMs, forKey: "windowMs") } }
    @Published var blockMove: Bool { didSet { UserDefaults.standard.set(blockMove, forKey: "blockMove") } }
    /// 界面语言："system" 跟随系统、"zh" 中文、"en" English
    @Published var language: String {
        didSet {
            UserDefaults.standard.set(language, forKey: "language")
            currentLanguage = language
        }
    }
    @Published var blockedCount: Int { didSet { UserDefaults.standard.set(blockedCount, forKey: "blockedCount") } }
    /// 事件监听是否已建立（有辅助功能权限）
    @Published private(set) var active = false

    private var tap: CFMachPort?
    private var lastKeyTime: CFAbsoluteTime = 0
    private var swallowedButtons = Set<Int64>()   // 按下事件被吞掉的按钮，对应的拖动/松开也要吞掉

    init() {
        let d = UserDefaults.standard
        d.register(defaults: ["enabled": true, "windowMs": Guard.defaultWindowMs, "blockMove": false,
                              "language": "system", "blockedCount": 0])
        enabled = d.bool(forKey: "enabled")
        windowMs = d.double(forKey: "windowMs")
        blockMove = d.bool(forKey: "blockMove")
        language = d.string(forKey: "language") ?? "system"
        blockedCount = d.integer(forKey: "blockedCount")
        currentLanguage = language
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        case .keyDown:
            // ⌘ / ⌃ 组合键是快捷键，不算打字，这样 ⌘+点击 等操作不受影响
            let f = event.flags
            if !f.contains(.maskCommand) && !f.contains(.maskControl) {
                lastKeyTime = CFAbsoluteTimeGetCurrent()
            }
            return pass
        default:
            break
        }

        let button = event.getIntegerValueField(.mouseEventButtonNumber)

        // 松开 / 拖动：如果对应的按下被吞了，就一起吞，避免出现“只有松开没有按下”的怪状态
        switch type {
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            if swallowedButtons.remove(button) != nil { return nil }
            return pass
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            if swallowedButtons.contains(button) { return nil }
        default:
            break
        }

        guard enabled else { return pass }
        let typingRecently = (CFAbsoluteTimeGetCurrent() - lastKeyTime) * 1000 < windowMs
        guard typingRecently else { return pass }

        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            swallowedButtons.insert(button)
            blockedCount += 1
            return nil
        case .scrollWheel:
            blockedCount += 1
            return nil
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return blockMove ? nil : pass
        default:
            return pass
        }
    }

    /// 创建事件监听；没有权限时返回 false
    func start() -> Bool {
        if tap != nil { return true }
        let types: [CGEventType] = [
            .keyDown,
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged,
            .mouseMoved, .scrollWheel,
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let g = Unmanaged<Guard>.fromOpaque(refcon!).takeUnretainedValue()
            return g.handle(type: type, event: event)
        }

        guard let t = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        tap = t
        active = true
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return true
    }
}

// MARK: - 界面语言

/// 当前语言设置；"system" 时跟随系统首选语言（中文系统显示中文，其他显示英文）
var currentLanguage = "system"
func L(_ zh: String, _ en: String) -> String {
    switch currentLanguage {
    case "zh": return zh
    case "en": return en
    default: return (Locale.preferredLanguages.first ?? "en").hasPrefix("zh") ? zh : en
    }
}

// MARK: - 设置窗口

struct SettingsView: View {
    @ObservedObject var g: Guard
    @ObservedObject var login: LoginItem

    var body: some View {
        Form {
            if !g.active {
                Section {
                    HStack {
                        Label(L("需要辅助功能权限才能工作", "Accessibility permission is required"),
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button(L("打开系统设置", "Open System Settings")) { openAccessibilitySettings() }
                    }
                }
            }

            Section {
                Toggle(L("打字时防误触", "Block trackpad while typing"), isOn: $g.enabled)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(L("按键后屏蔽时长", "Block duration after keypress"))
                        Spacer()
                        Text("\(Int(g.windowMs)) ms").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $g.windowMs, in: 100...2000, step: 50) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("100").font(.caption).foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Text("2000").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text(L("误触多就调长，觉得打完字点击有延迟就调短。",
                               "Raise it if stray touches get through; lower it if clicks feel delayed after typing."))
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(L("恢复默认", "Reset")) { g.windowMs = Guard.defaultWindowMs }
                            .controlSize(.small)
                            .disabled(g.windowMs == Guard.defaultWindowMs)
                    }
                }
                Toggle(L("打字时也锁定光标移动", "Also freeze pointer while typing"), isOn: $g.blockMove)
            }

            Section {
                Picker(L("语言", "Language"), selection: $g.language) {
                    Text(L("跟随系统", "System Default")).tag("system")
                    Text("简体中文").tag("zh")
                    Text("English").tag("en")
                }
                Toggle(L("登录时自动启动", "Launch at login"), isOn: Binding(
                    get: { login.enabled },
                    set: { login.set($0) }
                ))
                if let loginError = login.error {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section {
                HStack {
                    Text(L("已拦截误触", "Accidental touches blocked"))
                    Spacer()
                    Text("\(g.blockedCount)").monospacedDigit().foregroundStyle(.secondary)
                    Button(L("清零", "Reset")) { g.blockedCount = 0 }
                        .controlSize(.small)
                        .disabled(g.blockedCount == 0)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

}

/// 「登录时自动启动」的状态
final class LoginItem: ObservableObject {
    @Published private(set) var enabled = SMAppService.mainApp.status == .enabled
    @Published private(set) var error: String?

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch let e {
            error = L("设置失败：\(e.localizedDescription) 可以手动在「系统设置 → 通用 → 登录项」里添加。",
                      "Failed: \(e.localizedDescription) You can add it manually in System Settings → General → Login Items.")
        }
        enabled = SMAppService.mainApp.status == .enabled
    }
}

func openAccessibilitySettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
        NSWorkspace.shared.open(url)
    }
}

// MARK: - 菜单栏界面

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let guardian = Guard()
    var statusItem: NSStatusItem!
    var retryTimer: Timer?
    var settingsWindow: NSWindow?
    var observer: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()

        // 设置窗口里改了开关，菜单栏图标也跟着变
        observer = guardian.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateIcon() }
        }

        if !guardian.start() {
            // 弹出系统的辅助功能授权提示，然后每 2 秒重试一次
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
            retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
                guard let self else { return }
                if self.guardian.start() { timer.invalidate() }
            }
        }
    }

    func updateIcon() {
        guard let button = statusItem.button else { return }
        if button.image == nil {
            let image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "TypingGuard")
            image?.isTemplate = true
            button.image = image
        }
        let dimmed = !guardian.enabled || !guardian.active
        if button.appearsDisabled != dimmed { button.appearsDisabled = dimmed }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !guardian.active {
            let warn = NSMenuItem(title: L("⚠️ 需要辅助功能权限", "⚠️ Accessibility Permission Needed"),
                                  action: #selector(openAccessibility), keyEquivalent: "")
            warn.target = self
            menu.addItem(warn)
            menu.addItem(.separator())
        }

        let toggle = NSMenuItem(title: L("打字时防误触", "Block Trackpad While Typing"),
                                action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        toggle.state = guardian.enabled ? .on : .off
        menu.addItem(toggle)

        menu.addItem(.separator())
        let settings = NSMenuItem(title: L("设置…", "Settings…"), action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(NSMenuItem(title: L("退出", "Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc func toggleEnabled() { guardian.enabled.toggle() }
    @objc func openAccessibility() { openAccessibilitySettings() }

    @objc func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(g: guardian, login: LoginItem())))
            window.title = "TypingGuard"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - 启动

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // 只在菜单栏显示，不占 Dock
app.run()
