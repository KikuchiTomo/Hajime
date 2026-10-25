import AppKit
import os
import S90Application
import S90Domain

/// 入力メニュー(メニューバーの「あ」)に出す設定の項目を作る．
@MainActor
final class InputMenuBuilder: NSObject {
    private let settings: any SettingsStoring
    private let openSettings: () -> Void
    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "settings")

    init(settings: any SettingsStoring, openSettings: @escaping () -> Void) {
        self.settings = settings
        self.openSettings = openSettings
    }

    func makeMenu() -> NSMenu {
        let current = settings.current
        let menu = NSMenu()
        let open = NSMenuItem(title: UIStrings.Menu.openSettings, action: #selector(showSettings), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        menu.addItem(toggle(UIStrings.Menu.liveConversion, isOn: current.liveConversion, action: #selector(toggleLiveConversion)))
        menu.addItem(toggle(UIStrings.Menu.variantRow, isOn: current.showsVariantRow, action: #selector(toggleVariantRow)))
        menu.addItem(choices(UIStrings.Menu.presentation, CandidatePresentation.allCases, selected: current.candidatePresentation,
                             label: UIStrings.Menu.label(for:), action: #selector(selectPresentation)))
        menu.addItem(.separator())
        menu.addItem(choices(UIStrings.Menu.typoCorrection, TypoCorrectionLevel.allCases, selected: current.typoCorrection,
                             label: UIStrings.Menu.label(for:), action: #selector(selectTypoCorrection)))
        menu.addItem(choices(UIStrings.Menu.yenKey, YenKeyPolicy.allCases, selected: current.yenKey,
                             label: UIStrings.Menu.label(for:), action: #selector(selectYenKey)))
        menu.addItem(choices(UIStrings.Menu.theme, ThemePreference.allCases, selected: current.theme,
                             label: UIStrings.Menu.label(for:), action: #selector(selectTheme)))
        return menu
    }

    private func toggle(_ title: String, isOn: Bool, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = isOn ? .on : .off
        return item
    }

    private func choices<Value: RawRepresentable & Equatable>(
        _ title: String, _ values: [Value], selected: Value, label: (Value) -> String, action: Selector
    ) -> NSMenuItem where Value.RawValue == String {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for value in values {
            let item = NSMenuItem(title: label(value), action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = value.rawValue
            item.state = value == selected ? .on : .off
            submenu.addItem(item)
        }
        parent.submenu = submenu
        return parent
    }

    private func update(_ change: (inout Settings) -> Void) {
        do {
            try settings.update(change)
        } catch {
            logger.error("設定を保存できませんでした: \(String(describing: error), privacy: .public)")
        }
    }

    @objc private func showSettings() { openSettings() }
    @objc private func toggleLiveConversion() { update { $0.liveConversion.toggle() } }
    @objc private func toggleVariantRow() { update { $0.showsVariantRow.toggle() } }

    @objc private func selectTypoCorrection(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let value = TypoCorrectionLevel(rawValue: raw) else { return }
        update { $0.typoCorrection = value }
    }

    @objc private func selectYenKey(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let value = YenKeyPolicy(rawValue: raw) else { return }
        update { $0.yenKey = value }
    }

    @objc private func selectPresentation(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let value = CandidatePresentation(rawValue: raw) else { return }
        update { $0.candidatePresentation = value }
    }

    @objc private func selectTheme(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let value = ThemePreference(rawValue: raw) else { return }
        update { $0.theme = value }
    }
}
