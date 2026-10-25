import AppKit
import os
import S90Domain
import S90Persistence
import SwiftUI

/// 設定の画面を出すウィンドウ．入力メニューの「設定を開く」から出す
@MainActor
final class SettingsWindowController {
    private let model: SettingsModel
    private var window: NSWindow?

    init(settings: FileSettingsStore, resetLearning: @escaping () -> Void) {
        model = SettingsModel(store: settings, resetLearning: resetLearning)
    }

    func show() {
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
    private let store: FileSettingsStore
    private let resetLearningAction: () -> Void
    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "settings")

    init(store: FileSettingsStore, resetLearning: @escaping () -> Void) {
        self.store = store
        self.settings = store.current
        self.resetLearningAction = resetLearning
        // 入力メニューから変えたときも画面に映す
        store.observe { [weak self] in self?.settings = $0 }
    }

    func binding<Value>(_ keyPath: WritableKeyPath<S90Domain.Settings, Value>) -> Binding<Value> {
        Binding(get: { self.settings[keyPath: keyPath] }, set: { value in self.update { $0[keyPath: keyPath] = value } })
    }

    func update(_ change: (inout S90Domain.Settings) -> Void) {
        do {
            try store.update(change)
        } catch {
            logger.error("設定を保存できませんでした: \(String(describing: error), privacy: .public)")
            message = UIStrings.Settings.saveFailed
        }
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

    // MARK: ユーザー辞書

    func addEntry(reading: String, word: String) -> Bool {
        let entry = UserDictionaryEntry(reading: reading.trimmingCharacters(in: .whitespaces), word: word.trimmingCharacters(in: .whitespaces))
        guard entry.isValid, settings.userDictionary.count < DefaultSettings.maximumUserDictionaryEntries else {
            message = UIStrings.Settings.invalidEntry
            return false
        }
        update { current in
            if !current.userDictionary.contains(entry) { current.userDictionary.append(entry) }
        }
        return true
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
            let entries = try UserDictionaryFile.read(from: url)
            update { current in
                var seen = Set(current.userDictionary)
                for entry in entries where current.userDictionary.count < DefaultSettings.maximumUserDictionaryEntries && seen.insert(entry).inserted {
                    current.userDictionary.append(entry)
                }
            }
            message = UIStrings.Settings.imported(entries.count)
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
