import AppKit
import S90Application
import S90Domain

/// 連想の辞書(R-18)の取り込み・取り込み直し・削除・並べ替え
extension SettingsModel {
    /// 連想の辞書のファイルを選んで取り込む．existing を渡すと，その辞書を取り込み直す(名前はそのまま)．
    /// 読み書きは core(SettingsFiles)が行う(Windows のエンジンと同じ)
    func importAssociationFile(replacing existing: AssociationDictionary? = nil) {
        guard let files, associations != nil else { return }
        guard existing != nil || settings.associationDictionaries.count < DefaultSettings.maximumAssociationDictionaries else {
            message = UIStrings.Association.tooMany
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        isImportingDictionary = true
        Task {
            defer { isImportingDictionary = false }
            do throws(SettingsFileFailure) {
                let imported = try await files.importAssociationDictionary(from: source.path, replacing: existing?.id)
                message = UIStrings.Association.imported(imported.groupCount)
            } catch {
                logger.error("連想の辞書を取り込めませんでした: \(String(describing: error), privacy: .public)")
                switch error {
                case .tooMany: message = UIStrings.Association.tooMany
                case .writeFailed: message = UIStrings.Settings.saveFailed
                default: message = UIStrings.Association.importFailed
                }
            }
        }
    }

    func removeAssociationDictionary(_ dictionary: AssociationDictionary) {
        do {
            try files?.removeAssociationDictionary(id: dictionary.id)
        } catch {
            if error == .writeFailed { message = UIStrings.Settings.saveFailed }
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
