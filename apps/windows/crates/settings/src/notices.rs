#![forbid(unsafe_code)]

//! 謝辞(配布物に入れた THIRD_PARTY_NOTICES.md)を項目に分ける．macOS の Acknowledgement と同じ分け方

use std::sync::OnceLock;

/// 謝辞の 1 項目．「## 名前」から次の「## 」までを，出どころ(URL などの行)とライセンスの全文(コードブロック)に分ける
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Acknowledgement {
    pub name: String,
    pub sources: Vec<String>,
    pub license: Option<String>,
}

/// マークダウンを項目に分ける．ライセンスの全文の中にも「## 」で始まる行があるので，コードブロックの中では項目を区切らない
pub fn parse(markdown: &str) -> Vec<Acknowledgement> {
    let mut items: Vec<Acknowledgement> = Vec::new();
    let mut license: Vec<&str> = Vec::new();
    let mut in_code = false;
    for line in markdown.lines() {
        if line.starts_with("```") {
            if in_code {
                if let Some(last) = items.last_mut() {
                    last.license = Some(license.join("\n"));
                }
            }
            license.clear();
            in_code = !in_code;
        } else if in_code {
            license.push(line);
        } else if let Some(name) = line.strip_prefix("## ") {
            items.push(Acknowledgement {
                name: name.to_string(),
                ..Acknowledgement::default()
            });
        } else if !line.is_empty() {
            if let Some(last) = items.last_mut() {
                last.sources.push(line.to_string());
            }
        }
    }
    items
}

/// 出どころの行を，前置き(「改変したもの: 」など)・URL・後ろの文に分ける．URL が無ければ None．
/// URL は「https://」から，空白・ASCII でない文字・括弧の手前までとし，末尾の句読点は含めない
/// (「…/hajime-dictionary(v0.1.1)．」の括弧や句点まで URL にしない)．macOS の Acknowledgement.urlRange と同じ決まり
pub fn split_url(line: &str) -> Option<(&str, &str, &str)> {
    const SCHEME: &str = "https://";
    let start = line.find(SCHEME)?;
    let rest = &line[start..];
    let mut end = rest
        .find(|c: char| !c.is_ascii() || c.is_whitespace() || "()<>\"'`".contains(c))
        .unwrap_or(rest.len());
    while rest[..end].ends_with(|c: char| ".,;:!?".contains(c)) {
        end -= 1;
    }
    (end > SCHEME.len()).then(|| (&line[..start], &rest[..end], &rest[end..]))
}

/// 配布物に入れた謝辞の項目(実行ファイルと同じディレクトリ．tools/windows/stage.ps1)．読めなければ空．
/// ファイルは配布物の中で変わらないので，初めて使うときに 1 回だけ読む(ページの行の名前に使うため 'static で持つ)
pub fn installed() -> &'static [Acknowledgement] {
    const NOTICES_FILE: &str = "THIRD_PARTY_NOTICES.md";
    static ITEMS: OnceLock<Vec<Acknowledgement>> = OnceLock::new();
    ITEMS.get_or_init(|| {
        std::env::current_exe()
            .ok()
            .and_then(|path| path.parent().map(|dir| dir.join(NOTICES_FILE)))
            .and_then(|path| std::fs::read_to_string(path).ok())
            .map(|text| parse(&text))
            .unwrap_or_default()
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 見出しごとに出どころとライセンスに分ける() {
        let markdown = "# 謝辞\n\n前書き\n\n## A\n\nhttps://example.com/a\nMIT\n\n```\nCopyright A\n## 全文の中の見出し\n```\n\n## B\n\n改変したもの: https://example.com/b\n";
        let items = parse(markdown);
        assert_eq!(items.len(), 2);
        assert_eq!(items[0].name, "A");
        assert_eq!(items[0].sources, vec!["https://example.com/a", "MIT"]);
        assert_eq!(
            items[0].license.as_deref(),
            Some("Copyright A\n## 全文の中の見出し")
        );
        assert_eq!(items[1].name, "B");
        assert_eq!(items[1].license, None);
    }

    #[test]
    fn 行の中の_url_を分ける() {
        assert_eq!(
            split_url("改変したもの: https://example.com/b"),
            Some(("改変したもの: ", "https://example.com/b", ""))
        );
        assert_eq!(
            split_url("https://example.com"),
            Some(("", "https://example.com", ""))
        );
        assert_eq!(split_url("MIT License"), None);
    }

    #[test]
    fn url_に続く括弧や文は_url_にしない() {
        assert_eq!(
            split_url("https://github.com/a/b(v0.1.1)．辞書として同梱"),
            Some(("", "https://github.com/a/b", "(v0.1.1)．辞書として同梱"))
        );
        assert_eq!(
            split_url("https://github.com/google/mozc (the presets)"),
            Some(("", "https://github.com/google/mozc", " (the presets)"))
        );
        assert_eq!(
            split_url("Wikidata(https://www.wikidata.org/)．"),
            Some(("Wikidata(", "https://www.wikidata.org/", ")．"))
        );
        assert_eq!(
            split_url("詳しくは https://example.com/a."),
            Some(("詳しくは ", "https://example.com/a", "."))
        );
        assert_eq!(split_url("https://"), None);
    }

    #[test]
    fn リポジトリの謝辞を分けられる() {
        let markdown = include_str!("../../../../../THIRD_PARTY_NOTICES.md");
        let items = parse(markdown);
        assert!(items.len() >= 10);
        assert!(items.iter().all(|item| !item.name.is_empty()));
        assert!(items.iter().any(|item| item.license.is_some()));
        // 出どころの URL は，空白や括弧や全角の文字を含まない
        for (_, url, _) in items
            .iter()
            .flat_map(|item| item.sources.iter().filter_map(|line| split_url(line)))
        {
            assert!(
                url.chars()
                    .all(|c| c.is_ascii_graphic() && !"()".contains(c)),
                "{url}"
            );
        }
    }
}
