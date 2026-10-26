import AppKit
import S90Domain
import S90Persistence

/// 取り込んだ辞書の取り込み・取り込み直し・削除・並べ替え(R-14)
extension SettingsModel {
    /// 辞書のファイルを選んで取り込む．existing を渡すと，その辞書を取り込み直す(名前と条件はそのまま)
    func importDictionaryFile(replacing existing: ImportedDictionary? = nil) {
        guard let store = dictionaries else { return }
        guard existing != nil || settings.importedDictionaries.count < DefaultSettings.maximumImportedDictionaries else {
            message = UIStrings.Dictionaries.tooMany
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        let dictionary = existing ?? ImportedDictionary(id: UUID().uuidString, name: source.deletingPathExtension().lastPathComponent, wordCount: 0)
        let destination = store.url(for: dictionary)
        isImportingDictionary = true
        // 大きな辞書は読むのに数秒かかるので，画面を止めないよう裏で読む
        Task.detached(priority: .userInitiated) {
            let result: Result<Int, Error>
            do {
                let words = try DictionaryFileReader.read(from: source)
                try ImportedDictionaryStore.write(words, to: destination)
                result = .success(words.count)
            } catch {
                result = .failure(error)
            }
            await MainActor.run { self.finishImport(dictionary, isNew: existing == nil, result: result) }
        }
    }

    private func finishImport(_ dictionary: ImportedDictionary, isNew: Bool, result: Result<Int, Error>) {
        isImportingDictionary = false
        switch result {
        case .success(let count):
            dictionaries?.reload(dictionary)
            var updated = dictionary
            updated.wordCount = count
            if update({ settings in
                if isNew {
                    settings.importedDictionaries.append(updated)
                } else if let index = settings.importedDictionaries.firstIndex(where: { $0.id == updated.id }) {
                    settings.importedDictionaries[index].wordCount = count
                }
            }) {
                message = UIStrings.Dictionaries.imported(count)
            } else if isNew {
                // 設定に残せなかった新しい辞書の索引は，どこからも使われないので消す
                dictionaries?.remove(dictionary)
            }
        case .failure(let error):
            logger.error("辞書を取り込めませんでした: \(String(describing: error), privacy: .public)")
            message = UIStrings.Dictionaries.importFailed
        }
    }

    func removeDictionary(_ dictionary: ImportedDictionary) {
        if update({ $0.importedDictionaries.removeAll { $0.id == dictionary.id } }) {
            dictionaries?.remove(dictionary)
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
