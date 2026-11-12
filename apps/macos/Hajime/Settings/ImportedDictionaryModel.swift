import AppKit
import HajimeApplication
import HajimeDomain

/// 取り込んだ辞書の取り込み・取り込み直し・削除・並べ替え(R-16)
extension SettingsModel {
    /// 辞書のファイルを選び，取り込む前に中身を見せる．existing を渡すと，その辞書を取り込み直す(名前と条件はそのまま)
    func importDictionaryFile(replacing existing: ImportedDictionary? = nil) {
        guard existing != nil || settings.importedDictionaries.count < DefaultSettings.maximumImportedDictionaries else {
            message = UIStrings.Dictionaries.tooMany
            return
        }
        chooseImport(.dictionary, replacing: existing?.id)
    }

    /// 中身を見せた辞書のファイルを取り込む．replacing を渡すと，その辞書を取り込み直す
    func importDictionary(path: String, replacing id: String?) {
        guard let files else { return }
        isImportingDictionary = true
        // 大きな辞書は読むのに数秒かかる．読むのはメインスレッドの外(SettingsFiles)なので，画面は止まらない
        Task {
            defer { isImportingDictionary = false }
            do throws(SettingsFileFailure) {
                let imported = try await files.importDictionary(from: path, replacing: id)
                message = UIStrings.Dictionaries.imported(imported.wordCount)
            } catch {
                logger.error("辞書を取り込めませんでした: \(String(describing: error), privacy: .public)")
                switch error {
                case .tooMany: message = UIStrings.Dictionaries.tooMany
                case .writeFailed: message = UIStrings.Settings.saveFailed
                default: message = UIStrings.Dictionaries.importFailed
                }
            }
        }
    }

    func removeDictionary(_ dictionary: ImportedDictionary) {
        do {
            try files?.removeDictionary(id: dictionary.id)
        } catch {
            // 一覧に無い辞書(ほかの Mac で消した)は消えているので知らせない
            if error == .writeFailed { message = UIStrings.Settings.saveFailed }
        }
    }

    /// 一覧の中で 1 つ上(offset -1)か下(+1)に動かす．上ほど優先する
    func moveDictionary(_ dictionary: ImportedDictionary, by offset: Int) {
        update { settings in
            guard let index = settings.importedDictionaries.firstIndex(where: { $0.id == dictionary.id }) else { return }
            let target = index + offset
            guard settings.importedDictionaries.indices.contains(target) else { return }
            settings.importedDictionaries.swapAt(index, target)
        }
    }

    func updateDictionary(_ id: String, _ change: @escaping (inout ImportedDictionary) -> Void) {
        update { settings in
            guard let index = settings.importedDictionaries.firstIndex(where: { $0.id == id }) else { return }
            change(&settings.importedDictionaries[index])
        }
    }

    /// アプリの条件に足すアプリを選ぶ(/Applications から)．選んだアプリのバンドル ID で chosen を呼ぶ
    func chooseApplicationID(then chosen: @escaping @MainActor (String) -> Void) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        FilePanel.chooseOne(panel) { url in
            if let identifier = Bundle(url: url)?.bundleIdentifier { chosen(identifier) }
        }
    }
}
