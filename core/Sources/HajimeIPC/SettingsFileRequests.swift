import Foundation
import HajimeApplication
import HajimeDomain

/// 設定の画面から頼まれる同期とファイルの読み書き(R-15・R-16，バックアップ，除外設定の CSV，決まりの一覧)．
///
/// 同期の操作はすぐに答える．ファイルの読み書きは大きな辞書で数秒かかるので，EngineService.reply が .later を返し，
/// 名前付きパイプのスレッドで待つ(メインスレッドは止めないので，入力の処理は続く)．同時に動かすのは 1 つだけ
extension EngineService {
    /// 同期の要求に答える．同期の要求でなければ nil
    func syncResponse(for request: WireRequestBody) -> WireResponseBody? {
        switch request {
        case .readSync, .setSyncFolder, .setSyncEnabled, .setSyncScope, .setSyncLocalField, .syncNow:
            break
        default:
            return nil
        }
        guard let sync else { return .error(code: .malformed) }
        do {
            switch request {
            case .setSyncFolder(let path):
                try sync.chooseFolder(path: path)
            case .setSyncEnabled(let enabled):
                try sync.setEnabled(enabled)
            case .setSyncScope(let group, let scope):
                guard let group = SyncGroup(rawValue: group), let scope = SyncScope(rawValue: scope) else { return .error(code: .malformed) }
                try sync.setScope(scope, for: group)
            case .setSyncLocalField(let field, let isLocal):
                guard Settings.fieldNames.contains(field) else { return .error(code: .malformed) }
                try sync.setLocal(isLocal, field: field)
            case .syncNow:
                sync.syncNow()
            default:
                break
            }
        } catch SettingsFileFailure.invalidPath {
            return .fileFailed(reason: .invalidPath)
        } catch {
            return .fileFailed(reason: .writeFailed)
        }
        return .syncStatus(status: WireSyncStatus(sync.status))
    }

    /// ファイルの読み書きの仕事．ファイルの要求でなければ nil
    func fileWork(for request: WireRequestBody) -> (@MainActor (any SettingsFileHandling) async throws(SettingsFileFailure) -> WireResponseBody)? {
        switch request {
        case .importDictionary(let path, let replacing):
            return { files throws(SettingsFileFailure) in
                .dictionaryImported(dictionary: WireImportedDictionaryInfo(try await files.importDictionary(from: path, replacing: replacing)))
            }
        case .removeDictionary(let id):
            return { files throws(SettingsFileFailure) in
                try files.removeDictionary(id: id)
                return .done
            }
        case .importAssociationDictionary(let path, let replacing):
            return { files throws(SettingsFileFailure) in
                let dictionary = try await files.importAssociationDictionary(from: path, replacing: replacing)
                return .associationImported(dictionary: WireAssociationDictionaryInfo(
                    id: dictionary.id, name: dictionary.name, groupCount: UInt32(clamping: dictionary.groupCount)))
            }
        case .removeAssociationDictionary(let id):
            return { files throws(SettingsFileFailure) in
                try files.removeAssociationDictionary(id: id)
                return .done
            }
        case .importUserDictionary(let path):
            return { files throws(SettingsFileFailure) in Self.imported(try await files.importUserDictionary(from: path)) }
        case .exportUserDictionary(let path):
            return { files throws(SettingsFileFailure) in
                try await files.exportUserDictionary(to: path)
                return .done
            }
        case .exportSettings(let path):
            return { files throws(SettingsFileFailure) in
                try await files.exportSettings(to: path)
                return .done
            }
        case .importSettings(let path):
            return { files throws(SettingsFileFailure) in
                try await files.importSettings(from: path)
                return .done
            }
        case .importProfileRules(let path):
            return { files throws(SettingsFileFailure) in Self.imported(try await files.importProfileRules(from: path)) }
        case .exportProfileRules(let path):
            return { files throws(SettingsFileFailure) in
                try await files.exportProfileRules(to: path)
                return .done
            }
        case .importRuleList(let list, let path):
            return { files throws(SettingsFileFailure) in Self.imported(try await files.importRuleList(RuleList(list), from: path)) }
        case .exportRuleList(let list, let path):
            return { files throws(SettingsFileFailure) in
                try await files.exportRuleList(RuleList(list), to: path)
                return .done
            }
        default:
            return nil
        }
    }

    private static func imported(_ counts: (added: Int, skipped: Int)) -> WireResponseBody {
        .imported(added: UInt32(clamping: counts.added), skipped: UInt32(clamping: counts.skipped))
    }
}

extension WireSyncStatus {
    init(_ status: SyncStatus) {
        let state = status.state
        self.init(
            isEnabled: state.isEnabled,
            folderPath: state.folderPath,
            folderName: state.folderName,
            groups: SyncGroup.syncableCases.map { WireSyncGroupState(group: $0.rawValue, scope: state.scope(of: $0).rawValue, fields: $0.fieldNames) },
            localFields: state.localFields.sorted(),
            lastSyncedAt: state.ledger.lastSyncedAt.map { ISO8601DateFormatter().string(from: $0) },
            isSyncing: status.isSyncing,
            problem: status.problem.map(WireSyncProblem.init)
        )
    }
}

extension WireSyncProblem {
    init(_ problem: SyncProblem) {
        switch problem {
        case .failed: self = .failed
        case .unreadable: self = .unreadable
        case .folderUnavailable: self = .folderUnavailable
        }
    }
}

extension WireFileFailure {
    init(_ failure: SettingsFileFailure) {
        switch failure {
        case .invalidPath: self = .invalidPath
        case .notFound: self = .notFound
        case .tooLarge: self = .tooLarge
        case .unreadable: self = .unreadable
        case .empty: self = .empty
        case .notSettings: self = .notSettings
        case .tooMany: self = .tooMany
        case .unknownDictionary: self = .unknownDictionary
        case .writeFailed: self = .writeFailed
        }
    }
}

extension WireImportedDictionaryInfo {
    init(_ dictionary: ImportedDictionary) {
        self.init(id: dictionary.id, name: dictionary.name, wordCount: UInt32(clamping: dictionary.wordCount))
    }
}

extension RuleList {
    init(_ list: WireRuleList) {
        switch list {
        case .correctionRules: self = .correctionRules
        case .exceptions: self = .exceptions
        case .englishWords: self = .englishWords
        case .japaneseWords: self = .japaneseWords
        case .romaji: self = .romaji
        case .symbolSequences: self = .symbolSequences
        case .symbolReadings: self = .symbolReadings
        }
    }
}
