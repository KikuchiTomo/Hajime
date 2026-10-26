import AppKit
import S90Domain
import S90Persistence

/// 連想の辞書(R-18)の取り込み・取り込み直し・削除・並べ替え
extension SettingsModel {
    /// 連想の辞書のファイルを選んで取り込む．existing を渡すと，その辞書を取り込み直す(名前はそのまま)
    func importAssociationFile(replacing existing: AssociationDictionary? = nil) {
        guard let store = associations else { return }
        guard existing != nil || settings.associationDictionaries.count < DefaultSettings.maximumAssociationDictionaries else {
            message = UIStrings.Association.tooMany
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        let dictionary = existing ?? AssociationDictionary(id: UUID().uuidString, name: source.deletingPathExtension().lastPathComponent, groupCount: 0)
        let destination = store.url(for: dictionary)
        isImportingDictionary = true
        // 大きな辞書は読むのに数秒かかるので，画面を止めないよう裏で読む(取り込んだ辞書と同じ)
        Task.detached(priority: .userInitiated) {
            let result: Result<Int, Error>
            do {
                let groups = try AssociationFileReader.read(from: source)
                try AssociationDictionaryStore.write(groups, to: destination)
                result = .success(groups.count)
            } catch {
                result = .failure(error)
            }
            await MainActor.run { self.finishAssociationImport(dictionary, isNew: existing == nil, result: result) }
        }
    }

    private func finishAssociationImport(_ dictionary: AssociationDictionary, isNew: Bool, result: Result<Int, Error>) {
        isImportingDictionary = false
        switch result {
        case .success(let count):
            associations?.reload(dictionary)
            var updated = dictionary
            updated.groupCount = count
            if update({ settings in
                if isNew {
                    settings.associationDictionaries.append(updated)
                } else if let index = settings.associationDictionaries.firstIndex(where: { $0.id == updated.id }) {
                    settings.associationDictionaries[index].groupCount = count
                }
            }) {
                message = UIStrings.Association.imported(count)
            } else if isNew {
                // 設定に残せなかった新しい辞書の索引は，どこからも使われないので消す
                associations?.remove(dictionary)
            }
        case .failure(let error):
            logger.error("連想の辞書を取り込めませんでした: \(String(describing: error), privacy: .public)")
            message = UIStrings.Association.importFailed
        }
    }

    func removeAssociationDictionary(_ dictionary: AssociationDictionary) {
        if update({ $0.associationDictionaries.removeAll { $0.id == dictionary.id } }) {
            associations?.remove(dictionary)
        }
    }

    /// 一覧の中で 1 つ上(offset -1)か下(+1)に動かす．上の辞書の連想ほど先に出す
    func moveAssociationDictionary(_ dictionary: AssociationDictionary, by offset: Int) {
        update { settings in
            guard let index = settings.associationDictionaries.firstIndex(where: { $0.id == dictionary.id }) else { return }
            let target = index + offset
            guard settings.associationDictionaries.indices.contains(target) else { return }
            settings.associationDictionaries.swapAt(index, target)
        }
    }

    func updateAssociationDictionary(_ id: String, _ change: @escaping (inout AssociationDictionary) -> Void) {
        update { settings in
            guard let index = settings.associationDictionaries.firstIndex(where: { $0.id == id }) else { return }
            change(&settings.associationDictionaries[index])
        }
    }
}
