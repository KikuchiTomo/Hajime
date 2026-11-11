//! 更新の確認(R-19)．latest.json(https://haji.men/download/latest.json)を読み，今のバージョンより新しい配布物があるかを決める．
//!
//! 通信と画面は app::update が受け持ち，ここは OS に依存しない判断だけを置く(macOS でもテストを動かすため)．
//! latest.json は tools/release/upload_downloads.sh が書く:
//!   { "version": "0.2.7", "files": { "windows": "v0.2.7/Hajime-0.2.7.msi", … }, "sha256": { "windows": "<64 桁>", … },
//!     "releases": [{ "version": "0.2.7", "date": "2026-11-11", "notes": "### 追加\n\n- …" }] }

use serde::Deserialize;
use std::collections::BTreeMap;
use std::fmt;

/// latest.json の files・sha256 の鍵
pub const PLATFORM: &str = "windows";

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub struct Version {
    pub major: u32,
    pub minor: u32,
    pub patch: u32,
}

impl Version {
    /// 「0.2.7」の形だけを読む(前に v を付けない)
    pub fn parse(text: &str) -> Option<Self> {
        let mut parts = text.split('.');
        let mut next = || -> Option<u32> {
            let part = parts.next()?;
            if part.is_empty() || !part.bytes().all(|byte| byte.is_ascii_digit()) {
                return None;
            }
            part.parse().ok()
        };
        let version = Self {
            major: next()?,
            minor: next()?,
            patch: next()?,
        };
        parts.next().is_none().then_some(version)
    }
}

impl fmt::Display for Version {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "{}.{}.{}", self.major, self.minor, self.patch)
    }
}

#[derive(Debug, Deserialize)]
struct Manifest {
    version: String,
    #[serde(default)]
    files: BTreeMap<String, String>,
    #[serde(default)]
    sha256: BTreeMap<String, String>,
    #[serde(default)]
    releases: Vec<Release>,
}

#[derive(Debug, Deserialize)]
struct Release {
    version: String,
    #[serde(default)]
    date: String,
    #[serde(default)]
    notes: String,
}

/// 入れられる新しいバージョン
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Offer {
    pub version: Version,
    /// 配布物の URL(download_base_url の後ろに files の値を付けたもの)
    pub url: String,
    /// 保存するときの名前(Hajime-0.2.7.msi)
    pub file_name: String,
    /// 配布物の SHA-256(小文字の 16 進 64 桁)
    pub sha256: String,
    /// 今のバージョンより新しいバージョンの変更点(新しい順．長さは notes_length まで)
    pub notes: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Check {
    /// 今のバージョンが最新か，それより新しい
    UpToDate,
    Available(Offer),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
pub enum CheckError {
    #[error("latest.json を読めない")]
    Malformed,
    /// 新しいバージョンはあるが，この OS の配布物が無いか，場所や SHA-256 が無い・形が違う．
    /// 前の形の latest.json(sha256 と releases が無い)もこれになり，配布物は取らずにページを開いてもらう
    #[error("v{0} の配布物を確かめられない")]
    NoPackage(Version),
    #[error("今のバージョンを読めない")]
    UnknownCurrentVersion,
}

/// latest.json を読み，current(今のバージョン)より新しい配布物があるかを決める．
/// 配布物は base_url(https://haji.men/download/)の下の「v<バージョン>/<名前>」からだけ取る
pub fn check(
    manifest: &[u8],
    current: &str,
    base_url: &str,
    notes_length: usize,
) -> Result<Check, CheckError> {
    let current = Version::parse(current).ok_or(CheckError::UnknownCurrentVersion)?;
    let manifest: Manifest = serde_json::from_slice(manifest).map_err(|_| CheckError::Malformed)?;
    let latest = Version::parse(&manifest.version).ok_or(CheckError::Malformed)?;
    if latest <= current {
        return Ok(Check::UpToDate);
    }
    let unverifiable = CheckError::NoPackage(latest);
    let path = manifest.files.get(PLATFORM).ok_or(unverifiable)?;
    let file_name = package_name(path, latest).ok_or(unverifiable)?;
    let sha256 = manifest
        .sha256
        .get(PLATFORM)
        .and_then(|digest| normalized_digest(digest))
        .ok_or(unverifiable)?;
    Ok(Check::Available(Offer {
        version: latest,
        url: format!("{base_url}{path}"),
        file_name: file_name.to_string(),
        sha256,
        notes: notes(&manifest.releases, current, notes_length),
    }))
}

/// 「v0.2.7/Hajime-0.2.7.msi」の形(配る Worker の VERSIONED と同じ)で，フォルダが latest のバージョンのときだけ名前を返す
fn package_name(path: &str, latest: Version) -> Option<&str> {
    let (folder, name) = path.split_once('/')?;
    let version = Version::parse(folder.strip_prefix('v')?)?;
    let mut characters = name.chars();
    let first = characters.next()?;
    let valid = version == latest
        && first.is_ascii_alphanumeric()
        && characters.all(|character| {
            character.is_ascii_alphanumeric() || matches!(character, '.' | '_' | '-')
        })
        && name.ends_with(".msi");
    valid.then_some(name)
}

/// 64 桁の 16 進だけを受け付け，小文字にそろえる
pub fn normalized_digest(digest: &str) -> Option<String> {
    (digest.len() == 64 && digest.bytes().all(|byte| byte.is_ascii_hexdigit()))
        .then(|| digest.to_ascii_lowercase())
}

/// 今のバージョンより新しいバージョンの変更点を，新しい順に「v0.2.7 (2026-11-11)」の見出しを付けて並べる．
/// Markdown の見出しの「###」と箇条書きの「-」は，確かめる窓で読みやすい形にする．長ければ limit 文字で切る
fn notes(releases: &[Release], current: Version, limit: usize) -> String {
    let mut newer: Vec<(Version, &Release)> = releases
        .iter()
        .filter_map(|release| Some((Version::parse(&release.version)?, release)))
        .filter(|(version, _)| *version > current)
        .collect();
    newer.sort_by_key(|(version, _)| std::cmp::Reverse(*version));
    let mut text = String::new();
    for (version, release) in newer {
        if !text.is_empty() {
            text.push_str("\n\n");
        }
        if release.date.is_empty() {
            text.push_str(&format!("v{version}"));
        } else {
            text.push_str(&format!("v{version} ({})", release.date));
        }
        for line in release.notes.lines().map(str::trim_end) {
            if line.is_empty() {
                continue;
            }
            text.push('\n');
            if let Some(heading) = line.strip_prefix("### ") {
                text.push_str(&format!("【{heading}】"));
            } else if let Some(item) = line.strip_prefix("- ") {
                text.push_str(&format!("・{item}"));
            } else {
                text.push_str(line);
            }
        }
    }
    truncate(&text, limit)
}

/// 「https://<ホスト>/<道筋>」をホストと道筋(/ から)に分ける．利用者名・ポート・# の付いた URL は受け付けない
pub fn split_https(url: &str) -> Option<(&str, &str)> {
    let rest = url.strip_prefix("https://")?;
    let slash = rest.find('/')?;
    let (host, path) = rest.split_at(slash);
    let host_valid = !host.is_empty()
        && host
            .chars()
            .all(|character| character.is_ascii_alphanumeric() || matches!(character, '.' | '-'));
    (host_valid && !path.contains('#')).then_some((host, path))
}

/// SHA-256 を小文字の 16 進にする(latest.json の sha256 と比べる)
pub fn hex(digest: &[u8]) -> String {
    digest.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn truncate(text: &str, limit: usize) -> String {
    if text.chars().count() <= limit {
        return text.to_string();
    }
    let mut cut: String = text.chars().take(limit).collect();
    cut.push('…');
    cut
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cmp::Ordering;

    fn compare(left: &str, right: &str) -> Option<Ordering> {
        Some(Version::parse(left)?.cmp(&Version::parse(right)?))
    }

    const BASE: &str = "https://haji.men/download/";
    const DIGEST: &str = "0263829989B6FD954F72BAAF2FC64BC2E2F01D692D4DE72986EA808F6E99813F";

    fn manifest(version: &str, windows: &str, digest: &str) -> Vec<u8> {
        serde_json::json!({
            "version": version,
            "files": { "macos": format!("v{version}/Hajime-{version}.pkg"), "windows": windows },
            "sha256": { "macos": DIGEST, "windows": digest },
            "releases": [
                { "version": "0.2.8", "date": "2026-11-12", "notes": "### 修正\n\n- B を直しました (#2)" },
                { "version": "0.2.7", "date": "2026-11-11", "notes": "### 追加\n\n- A を足しました (#1)" },
                { "version": "0.2.6", "date": "2026-11-07", "notes": "### 修正\n\n- 古い変更 (#0)" }
            ]
        })
        .to_string()
        .into_bytes()
    }

    #[test]
    fn バージョンを読む() {
        assert_eq!(
            Version::parse("0.2.10"),
            Some(Version {
                major: 0,
                minor: 2,
                patch: 10
            })
        );
        for text in ["v0.2.7", "0.2", "0.2.7.1", "0.2.x", "0..7", "", "0.2.+7"] {
            assert_eq!(Version::parse(text), None, "{text}");
        }
        assert_eq!(compare("0.2.10", "0.2.9"), Some(Ordering::Greater));
        assert_eq!(compare("1.0.0", "0.99.99"), Some(Ordering::Greater));
    }

    #[test]
    fn 新しいバージョンがあれば配布物と変更点を返す() {
        let body = manifest("0.2.8", "v0.2.8/Hajime-0.2.8.msi", DIGEST);
        let Ok(Check::Available(offer)) = check(&body, "0.2.6", BASE, 1000) else {
            panic!("新しいバージョンがあるはず");
        };
        assert_eq!(offer.version.to_string(), "0.2.8");
        assert_eq!(
            offer.url,
            "https://haji.men/download/v0.2.8/Hajime-0.2.8.msi"
        );
        assert_eq!(offer.file_name, "Hajime-0.2.8.msi");
        assert_eq!(offer.sha256, DIGEST.to_ascii_lowercase());
        assert_eq!(
            offer.notes,
            "v0.2.8 (2026-11-12)\n【修正】\n・B を直しました (#2)\n\nv0.2.7 (2026-11-11)\n【追加】\n・A を足しました (#1)"
        );
    }

    #[test]
    fn 同じか古ければ最新とする() {
        let body = manifest("0.2.8", "v0.2.8/Hajime-0.2.8.msi", DIGEST);
        assert_eq!(check(&body, "0.2.8", BASE, 1000), Ok(Check::UpToDate));
        assert_eq!(check(&body, "0.3.0", BASE, 1000), Ok(Check::UpToDate));
    }

    #[test]
    fn 配布物の場所が決まりの形でなければ取らない() {
        for path in [
            "https://example.com/Hajime.msi",
            "../v0.2.8/Hajime-0.2.8.msi",
            "v0.2.8/../../Hajime-0.2.8.msi",
            "v0.2.8/sub/Hajime-0.2.8.msi",
            "v0.2.7/Hajime-0.2.7.msi",
            "v0.2.8/Hajime-0.2.8.exe",
            "v0.2.8/.msi",
            "v0.2.8/Hajime 0.2.8.msi",
            "v0.2.8/Hajime-0.2.8.msi?x=1",
        ] {
            let body = manifest("0.2.8", path, DIGEST);
            assert_eq!(
                check(&body, "0.2.6", BASE, 1000),
                Err(CheckError::NoPackage(Version::parse("0.2.8").unwrap())),
                "{path}"
            );
        }
    }

    #[test]
    fn sha256_が_64_桁の_16_進でなければ取らない() {
        for digest in ["", "abc", &DIGEST[1..], &format!("{}g", &DIGEST[1..])] {
            let body = manifest("0.2.8", "v0.2.8/Hajime-0.2.8.msi", digest);
            assert_eq!(
                check(&body, "0.2.6", BASE, 1000),
                Err(CheckError::NoPackage(Version::parse("0.2.8").unwrap()))
            );
        }
    }

    #[test]
    fn 読めない_json_や今のバージョンは誤りにする() {
        assert_eq!(
            check(b"not json", "0.2.6", BASE, 1000),
            Err(CheckError::Malformed)
        );
        let body = manifest("latest", "v0.2.8/Hajime-0.2.8.msi", DIGEST);
        assert_eq!(
            check(&body, "0.2.6", BASE, 1000),
            Err(CheckError::Malformed)
        );
        let body = manifest("0.2.8", "v0.2.8/Hajime-0.2.8.msi", DIGEST);
        assert_eq!(
            check(&body, "dev", BASE, 1000),
            Err(CheckError::UnknownCurrentVersion)
        );
    }

    #[test]
    fn https_の_url_をホストと道筋に分ける() {
        assert_eq!(
            split_https("https://haji.men/download/latest.json"),
            Some(("haji.men", "/download/latest.json"))
        );
        for url in [
            "http://haji.men/download/latest.json",
            "https://haji.men",
            "https://user@haji.men/x",
            "https://haji.men:8443/x",
            "https:///x",
            "https://haji.men/x#y",
        ] {
            assert_eq!(split_https(url), None, "{url}");
        }
    }

    #[test]
    fn ハッシュを小文字の_16_進にする() {
        assert_eq!(hex(&[0x00, 0xab, 0x0f]), "00ab0f");
    }

    #[test]
    fn 前の形の_latest_json_でも最新かどうかは決められる() {
        // sha256 と releases の無い形(v0.2.6 までの upload_downloads.sh が書いたもの)
        let body = br#"{"version":"0.2.6","files":{"macos":"v0.2.6/Hajime-0.2.6.pkg","windows":"v0.2.6/Hajime-0.2.6.msi"}}"#;
        assert_eq!(check(body, "0.2.6", BASE, 1000), Ok(Check::UpToDate));
        assert_eq!(check(body, "0.3.0", BASE, 1000), Ok(Check::UpToDate));
    }

    #[test]
    fn 前の形の_latest_json_で新しければ配布物を取らない() {
        let body = br#"{"version":"0.2.6","files":{"macos":"v0.2.6/Hajime-0.2.6.pkg","windows":"v0.2.6/Hajime-0.2.6.msi"}}"#;
        assert_eq!(
            check(body, "0.2.5", BASE, 1000),
            Err(CheckError::NoPackage(Version::parse("0.2.6").unwrap()))
        );
    }

    #[test]
    fn releases_が無くても配布物は取れ_変更点は空にする() {
        let body = serde_json::json!({
            "version": "0.2.8",
            "files": { "windows": "v0.2.8/Hajime-0.2.8.msi" },
            "sha256": { "windows": DIGEST }
        })
        .to_string();
        let Ok(Check::Available(offer)) = check(body.as_bytes(), "0.2.6", BASE, 1000) else {
            panic!("新しいバージョンがあるはず");
        };
        assert_eq!(offer.notes, "");
    }

    #[test]
    fn 変更点は上限で切る() {
        let body = manifest("0.2.8", "v0.2.8/Hajime-0.2.8.msi", DIGEST);
        let Ok(Check::Available(offer)) = check(&body, "0.2.6", BASE, 10) else {
            panic!("新しいバージョンがあるはず");
        };
        assert_eq!(offer.notes, "v0.2.8 (20…");
    }
}
