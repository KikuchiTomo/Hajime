import AppKit
import os
import S90Application
import S90Domain
import S90Persistence
import SwiftUI

/// 設定の画面を出すウィンドウ．入力メニューの「設定を開く」から出す
@MainActor
final class SettingsWindowController {
    private let model: SettingsModel
    private var window: NSWindow?

    init(settings: any SettingsStoring & SettingsObserving, usage: any UsageReading, resetLearning: @escaping () -> Void) {
        model = SettingsModel(store: settings, usage: usage, resetLearning: resetLearning)
    }

    /// 起動したときに読めず脇に置いた設定のファイルがあれば，最初に画面を開いたときに一度だけ知らせる
    func noteSetAsideFile(_ url: URL?) {
        guard let url else { return }
        model.message = UIStrings.Settings.setAside(url.lastPathComponent)
    }

    func show() {
        model.refreshUsage()
        let window = window ?? makeWindow()
        self.window = window
        // 入力メソッドは前面のアプリにならないので，開くときだけ前に出す
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SettingsView.size),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = UIStrings.Settings.windowTitle
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

/// 設定の画面と保存先のあいだを取り持つ．画面で変えた値はすぐに保存する
@MainActor
final class SettingsModel: ObservableObject {
    @Published private(set) var settings: S90Domain.Settings
    @Published var message: String?
    @Published private(set) var usageCounts: UsageCounts
    private let store: any SettingsStoring & SettingsObserving
    private let usage: (any UsageReading)?
    private let resetLearningAction: () -> Void
    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "settings")

    init(store: any SettingsStoring & SettingsObserving, usage: (any UsageReading)?, resetLearning: @escaping () -> Void) {
        self.store = store
        self.usage = usage
        self.settings = store.current
        self.usageCounts = usage?.counts ?? UsageCounts()
        self.resetLearningAction = resetLearning
        // 入力メニューから変えたときも画面に映す
        store.observe { [weak self] in self?.settings = $0 }
    }

    func binding<Value>(_ keyPath: WritableKeyPath<S90Domain.Settings, Value>) -> Binding<Value> {
        Binding(get: { self.settings[keyPath: keyPath] }, set: { value in self.update { $0[keyPath: keyPath] = value } })
    }

    /// 設定を変えて保存する．保存できなければ知らせて false を返す
    @discardableResult
    func update(_ change: (inout S90Domain.Settings) -> Void) -> Bool {
        do {
            try store.update(change)
            return true
        } catch {
            logger.error("設定を保存できませんでした: \(String(describing: error), privacy: .public)")
            message = UIStrings.Settings.saveFailed
            return false
        }
    }

    /// 画面を開いたときに，使い方の記録を読み直す
    func refreshUsage() {
        usageCounts = usage?.counts ?? UsageCounts()
    }

    func resetUsage() {
        usage?.reset()
        refreshUsage()
    }

    func resetLearning() {
        resetLearningAction()
        message = UIStrings.Settings.learningReset
    }

    func restoreDefaults() {
        // ユーザー辞書は既定に戻さない．登録した語を消すのは辞書の画面で行う
        update { current in
            let dictionary = current.userDictionary
            current = S90Domain.Settings()
            current.userDictionary = dictionary
        }
    }

    // MARK: アプリごとのプロファイル

    /// 先頭に足す．先にある規則を優先するので，利用者が足した規則が既定の規則より効く
    /// 保存できたら true．できなければ入力欄を残す
    func addProfileRule(prefix: String, profile: AppProfile) -> Bool {
        let trimmed = prefix.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        return update { current in
            current.profileRules.removeAll { $0.applicationPrefix == trimmed }
            current.profileRules.insert(ProfileRule(applicationPrefix: trimmed, profile: profile), at: 0)
        }
    }

    // MARK: ローマ字

    func addRomajiRule(keys: String, kana: String) -> Bool {
        let rule = RomajiRule(keys: keys.trimmingCharacters(in: .whitespaces).lowercased(), kana: kana.trimmingCharacters(in: .whitespaces))
        guard rule.isValid, settings.customRomaji.count < DefaultSettings.maximumRomajiRules else {
            message = UIStrings.Settings.invalidRomaji
            return false
        }
        return update { current in
            current.customRomaji.removeAll { $0.keys == rule.keys }
            current.customRomaji.append(rule)
        }
    }

    // MARK: ユーザー辞書

    func addEntry(reading: String, word: String) -> Bool {
        var entries = settings.userDictionary
        switch UserDictionaryEditing.add(reading: reading, word: word, to: &entries) {
        case .added:
            // 保存できなければ false を返し，打った語を入力欄に残す
            return update { $0.userDictionary = entries }
        case .alreadyRegistered:
            return true
        case .invalid:
            message = UIStrings.Settings.invalidEntry
        case .full:
            message = UIStrings.Settings.dictionaryFull
        }
        return false
    }

    func removeEntries(_ entries: Set<UserDictionaryEntry>) {
        update { $0.userDictionary.removeAll { entries.contains($0) } }
    }

    /// 「読み<タブ>語」の行が並んだテキストのファイルから取り込む(Google 日本語入力・ATOK の書き出しと同じ形)
    func importDictionary() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .tabSeparatedText, .commaSeparatedText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            var entries = settings.userDictionary
            let added = UserDictionaryEditing.merge(try UserDictionaryFile.read(from: url), into: &entries)
            if update({ $0.userDictionary = entries }) {
                message = UIStrings.Settings.imported(added)
            }
        } catch {
            message = UIStrings.Settings.importFailed
        }
    }

    func exportDictionary() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = UIStrings.Settings.exportFileName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try UserDictionaryFile.write(settings.userDictionary, to: url)
        } catch {
            message = UIStrings.Settings.exportFailed
        }
    }
}
