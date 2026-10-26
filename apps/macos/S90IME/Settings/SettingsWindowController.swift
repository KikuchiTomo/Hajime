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
    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "settings")

    private let sync: SyncCoordinator

    init(settings: any SettingsStoring & SettingsObserving, usage: any UsageReading, sync: SyncCoordinator, dictionaries: ImportedDictionaryStore? = nil,
         associations: AssociationDictionaryStore? = nil,
         resetLearning: @escaping () -> Void, previewLanguage: ((String, String?) -> [WordLanguagePreview.Word])? = nil) {
        model = SettingsModel(store: settings, usage: usage, dictionaries: dictionaries, associations: associations, resetLearning: resetLearning,
                              previewLanguage: previewLanguage)
        self.sync = sync
    }

    /// 起動したときに読めず脇に置いた設定のファイルがあれば，最初に画面を開いたときに一度だけ知らせる
    func noteSetAsideFile(_ url: URL?) {
        guard let url else { return }
        model.message = UIStrings.Settings.setAside(url.lastPathComponent)
    }

    /// 設定の画面を前に出して，キーボードの入力を受けられるようにする．
    ///
    /// 入力メソッドは前面に出られないアプリ(Info.plist の LSBackgroundOnly)なので，そのままでは窓がほかのアプリの窓の後ろに隠れ，
    /// 入力欄にも打てない(実機のログで visible=true key=false だった)．開いているあいだだけ前面に出られる補助アプリ(.accessory)にし，
    /// 閉じたら前面に出ないアプリ(.prohibited)に戻す．Dock とメニューバーには出ない
    func show() {
        model.refreshUsage()
        let window = window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        // 前に出たかは，切り替えが済んだあとに記録する
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [logger] in
            logger.notice("設定の画面: visible=\(window.isVisible, privacy: .public) key=\(window.isKeyWindow, privacy: .public) active=\(NSApp.isActive, privacy: .public)")
        }
    }

    private func makeWindow() -> NSWindow {
        Self.makeWindow(model: model, sync: sync, navigation: SettingsNavigation())
    }

    /// 設定の画面の窓を作る．計測と書き出し(デバッグビルド)でも同じ窓を使う
    static func makeWindow(model: SettingsModel, sync: SyncCoordinator, navigation: SettingsNavigation) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SettingsView.size),
            // 左の一覧をタイトルバーの下まで伸ばす(システム設定と同じ見た目)
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = UIStrings.Settings.windowTitle
        // タイトルバーを透明にすると，スクロールした中身が見出しの下に透けて重なる．
        // 窓にツールバーを持たせ，SwiftUI の見出しと検索欄をそこに出して，OS にタイトルバーの地を塗らせる
        window.toolbar = NSToolbar(identifier: "settings")
        window.toolbarStyle = .unified
        let hosting = NSHostingView(rootView: SettingsView(model: model, sync: sync, navigation: navigation))
        hosting.sceneBridgingOptions = [.toolbars, .title]
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        // いつも最前面に出す．macOS 14 からは，前面のアプリ(cmux など)が譲らない限り，ほかのアプリは前面に出られない
        // (実機の記録で visible=true key=false active=false だった)．前面に出られなくても，ほかのアプリの窓より上に浮かせて見えるようにし，
        // 押せばキーボードの入力を受けられる．フルスクリーンのアプリの操作スペースにも，今いる操作スペースに出す
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.center()
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            // 閉じたら前面に出ないアプリに戻す(入力メソッドとして，ほかのアプリの前に出ない)
            MainActor.assumeIsolated { _ = NSApp.setActivationPolicy(.prohibited) }
        }
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
    let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "settings")
    /// 取り込んだ辞書の索引(R-16)．無ければ辞書を取り込めない
    let dictionaries: ImportedDictionaryStore?
    /// 辞書を取り込んでいるあいだ true(取り込みは数秒かかることがある)
    @Published var isImportingDictionary = false
    /// 連想の辞書の索引(R-18)．無ければ連想の辞書を取り込めない
    let associations: AssociationDictionaryStore?
    /// 英字入力(自動)で打った文を語ごとに見分けた結果(「試す」)．無ければ「試す」を出さない
    let previewLanguage: ((String, String?) -> [WordLanguagePreview.Word])?

    init(store: any SettingsStoring & SettingsObserving, usage: (any UsageReading)?, dictionaries: ImportedDictionaryStore? = nil,
         associations: AssociationDictionaryStore? = nil,
         resetLearning: @escaping () -> Void, previewLanguage: ((String, String?) -> [WordLanguagePreview.Word])? = nil) {
        self.previewLanguage = previewLanguage
        self.store = store
        self.usage = usage
        self.dictionaries = dictionaries
        self.associations = associations
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
            let imported = current.importedDictionaries
            let associations = current.associationDictionaries
            current = S90Domain.Settings()
            current.userDictionary = dictionary
            current.importedDictionaries = imported
            current.associationDictionaries = associations
        }
    }

    // MARK: 決まりの一覧

    /// 一覧を変える．change が false を返したら(形が誤っているか上限を超える)failure を知らせる．保存して変えられたら true
    func editRules(failure: String, _ change: (inout S90Domain.Settings) -> Bool) -> Bool {
        var changed = false
        guard update({ changed = change(&$0) }) else { return false }
        if !changed { message = failure }
        return changed
    }

    /// 決まりの一覧をファイル(「左<タブ>右」の行)から読み込む．merge で設定に足し，足した数を知らせる
    func importRuleList(_ merge: ([RuleListFile.Row], inout S90Domain.Settings) -> Int) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .tabSeparatedText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let rows = try RuleListFile.read(from: url)
            var added = 0
            if update({ added = merge(rows, &$0) }) {
                message = UIStrings.More.importedRules(added)
            }
        } catch {
            message = UIStrings.Settings.importFailed
        }
    }

    func exportRuleList(_ rows: [RuleListFile.Row], fileName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try RuleListFile.write(rows, to: url)
        } catch {
            message = UIStrings.Settings.exportFailed
        }
    }

    // MARK: ユーザー辞書

    /// 語を登録する．replacing を渡すとその語を書き換える(同じ位置に置く)．保存できなければ false を返し，打った語を入力欄に残す
    func saveEntry(replacing old: UserDictionaryEntry?, reading: String, word: String) -> Bool {
        var entries = settings.userDictionary
        let index = old.flatMap { entries.firstIndex(of: $0) }
        if let index { entries.remove(at: index) }
        switch UserDictionaryEditing.add(reading: reading, word: word, to: &entries) {
        case .added:
            if let index { entries.insert(entries.removeLast(), at: index) }
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

    /// 「読み<タブ>語」の行が並んだテキストのファイルから取り込む
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

    // MARK: 除外設定

    /// アプリを /Applications から選んで足す．バンドル ID を手で打たなくてよいように
    func addApplications(profile: AppProfile) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        let identifiers = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }.filter(ProfileRuleCSV.isValidIdentifier)
        guard !identifiers.isEmpty else {
            message = UIStrings.More.noBundleID
            return
        }
        update { current in
            current.profileRules.removeAll { identifiers.contains($0.applicationPrefix) }
            current.profileRules.insert(contentsOf: identifiers.map { ProfileRule(applicationPrefix: $0, profile: profile) }, at: 0)
        }
    }

    func importProfileRules() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let rules = try ProfileRuleFile.read(from: url)
            let identifiers = Set(rules.map(\.applicationPrefix))
            if update({ current in
                current.profileRules.removeAll { identifiers.contains($0.applicationPrefix) }
                current.profileRules.insert(contentsOf: rules, at: 0)
                current.clampToValidRanges()
            }) {
                message = UIStrings.More.importedRules(rules.count)
            }
        } catch {
            message = UIStrings.More.csvFailed
        }
    }

    func exportProfileRules() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = UIStrings.More.exportCSVFileName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ProfileRuleFile.write(settings.profileRules, to: url)
        } catch {
            message = UIStrings.Settings.exportFailed
        }
    }

    // MARK: バックアップ

    func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = UIStrings.More.exportSettingsFileName
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SettingsTransfer.write(settings, to: url)
        } catch {
            message = UIStrings.More.settingsExportFailed
        }
    }

    /// 読み込んだ設定ですべてを置き換える．読めない項目と範囲の外の値は既定値になる(SettingsTransfer)
    func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try SettingsTransfer.read(from: url)
            if update({ $0 = imported }) { message = UIStrings.More.settingsImported }
        } catch {
            message = UIStrings.More.settingsImportFailed
        }
    }

    // MARK: カスタムテーマ

    /// 新しいカスタムテーマの下書き．今使っているテーマ(既成のテーマかカスタムテーマ)の色を写す．保存はしない
    func draftCustomTheme() -> CustomTheme {
        var theme = settings.activeCustomTheme ?? Self.customTheme(from: settings.theme)
        theme.id = UUID().uuidString
        theme.name = UIStrings.More.newThemeName
        return theme
    }

    /// 今使っているテーマを複製して，新しいカスタムテーマにし，それを使う
    func duplicateCurrentTheme() {
        let source = settings.activeCustomTheme ?? Self.customTheme(from: settings.theme)
        duplicate(source)
    }

    /// カスタムテーマを複製して使う
    func duplicateCustomTheme(id: String) {
        guard let source = settings.customThemes.first(where: { $0.id == id }) else { return }
        duplicate(source)
    }

    private func duplicate(_ source: CustomTheme) {
        var theme = source
        theme.id = UUID().uuidString
        theme.name = String(UIStrings.More.copyName(source.name).prefix(DefaultSettings.maximumThemeNameLength))
        _ = saveCustomTheme(theme)
    }

    /// カスタムテーマを保存して使う．同じ id のテーマがあれば置き換え，無ければ足す．保存できたら true
    func saveCustomTheme(_ theme: CustomTheme) -> Bool {
        guard theme.isValid else {
            message = UIStrings.More.invalidTheme
            return false
        }
        guard settings.customThemes.contains(where: { $0.id == theme.id }) || settings.customThemes.count < DefaultSettings.maximumCustomThemes else {
            message = UIStrings.More.themesFull
            return false
        }
        return update { current in
            if let index = current.customThemes.firstIndex(where: { $0.id == theme.id }) {
                current.customThemes[index] = theme
            } else {
                current.customThemes.append(theme)
            }
            current.customThemeID = theme.id
        }
    }

    func deleteCustomTheme(id: String) {
        update { current in
            current.customThemes.removeAll { $0.id == id }
            if current.customThemeID == id { current.customThemeID = nil }
        }
    }

    /// 既成のテーマを選ぶ(カスタムテーマは使わない)
    func selectTheme(_ theme: ThemePreference) {
        update { current in
            current.theme = theme
            current.customThemeID = nil
        }
    }

    func selectCustomTheme(id: String) {
        update { $0.customThemeID = id }
    }

    /// 既成のテーマの色を写したカスタムテーマ．標準(glass)の色は OS の色なので，今の外観での色にする
    private static func customTheme(from preference: ThemePreference) -> CustomTheme {
        var resolved = ResolvedTheme.resolve(preference)
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = ResolvedTheme.resolve(preference)
        }
        func hex(_ color: NSColor) -> HexColor {
            var value = HexColor(red: 0, green: 0, blue: 0)
            NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
                let rgb = color.usingColorSpace(.sRGB) ?? .black
                value = HexColor(red: UInt8((rgb.redComponent * 255).rounded()), green: UInt8((rgb.greenComponent * 255).rounded()),
                                 blue: UInt8((rgb.blueComponent * 255).rounded()))
            }
            return value
        }
        return CustomTheme(
            id: UUID().uuidString, name: UIStrings.Choice.label(for: preference), base: preference,
            surface: hex(resolved.surface), text: hex(resolved.text), textMuted: hex(resolved.textMuted),
            selection: hex(resolved.selection), selectionText: hex(resolved.selectionText),
            correction: hex(resolved.correction), line: hex(resolved.line),
            cornerRadius: resolved.isRounded ? Double(resolved.cornerRadius) : 0
        )
    }

    // MARK: 情報

    var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }

    /// アプリに入れた利用表記(THIRD_PARTY_NOTICES.md)を項目に分けたもの．無ければ nil．
    /// 画面を描き直すたびにファイルを読み直さないよう，初めて使うときに一度だけ読む
    private(set) lazy var acknowledgements: [Acknowledgement]? = {
        guard let url = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return Acknowledgement.parse(text)
    }()
}
