import AppKit
import S90Application
import S90Domain

/// 取り込んだ辞書の取り込み・取り込み直し・削除・並べ替え(R-16)
extension SettingsModel {
    /// 辞書のファイルを選んで取り込む．existing を渡すと，その辞書を取り込み直す(名前と条件はそのまま)
    func importDictionaryFile(replacing existing: ImportedDictionary? = nil) {
        guard let files else { return }
        guard existing != nil || settings.importedDictionaries.count < DefaultSettings.maximumImportedDictionaries else {
            message = UIStrings.Dictionaries.tooMany
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        isImportingDictionary = true
        // 大きな辞書は読むのに数秒かかる．読むのはメインスレッドの外(SettingsFiles)なので，画面は止まらない
        Task {
            defer { isImportingDictionary = false }
            do throws(SettingsFileFailure) {
                let imported = try await files.importDictionary(from: source.path, replacing: existing?.id)
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

    /// アプリの条件に足すアプリを選ぶ(/Applications から)
    func chooseApplicationID() -> String? {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }
}
