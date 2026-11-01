#!/usr/bin/env ruby
# frozen_string_literal: true

# Extract homophone groups (同音異義語) from Mozc's dictionary_oss.
#
#   ruby extract_groups.rb --mozc-dir path/to/dictionary_oss \
#        --usage-dict path/to/usage_dict.txt -o work/groups.jsonl
#
# A group = one reading + POS (+ conjugation type) with 2 or more kanji
# spellings that are common enough (Mozc cost <= --max-cost).
# Groups whose reading is already covered by usage_dict.txt are skipped
# (or, with --include-partial, kept when some spellings are still missing).
# Output is sorted so the most frequent confusions come first.

require "optparse"
require "fileutils"
require "set"
require_relative "lib/common"

opts = {
  mozc_dir: "data",
  usage_dict: "data/usage_dict.txt",
  out: "work/groups.jsonl",
  max_cost: 10000,
  min_candidates: 2,
  include_partial: false,
  limit: nil,
}
OptionParser.new do |o|
  o.banner = "Usage: ruby extract_groups.rb [options]"
  o.on("--mozc-dir DIR", "Directory with dictionary0*.txt and id.def") { |v| opts[:mozc_dir] = v }
  o.on("--usage-dict FILE", "Existing usage_dict.txt (to skip covered readings)") { |v| opts[:usage_dict] = v }
  o.on("-o", "--out FILE", "Output JSONL") { |v| opts[:out] = v }
  o.on("--max-cost N", Integer, "Max Mozc cost for a spelling (lower = more common, default 10000)") { |v| opts[:max_cost] = v }
  o.on("--min-candidates N", Integer, "Min kanji spellings per group (default 2)") { |v| opts[:min_candidates] = v }
  o.on("--include-partial", "Keep readings already in usage_dict if some spellings are missing") { opts[:include_partial] = true }
  o.on("--limit N", Integer, "Write only the top N groups") { |v| opts[:limit] = v }
end.parse!

KANJI = /\p{Han}/
HIRAGANA_ONLY = /\A[\p{Hiragana}ー]+\z/

NOUN_SUB = %w[一般 サ変接続 形容動詞語幹 副詞可能 ナイ形容詞語幹].freeze

# Mozc's id.def lumps most godan verbs into "五段動詞"; usage_dict.txt uses
# IPAdic-style names, so derive them from the last kana.
GODAN_BY_ENDING = {
  "う" => "五段・ワ行促音便", "く" => "五段・カ行イ音便", "ぐ" => "五段・ガ行",
  "す" => "五段・サ行", "つ" => "五段・タ行", "ぬ" => "五段・ナ行",
  "ぶ" => "五段・バ行", "む" => "五段・マ行", "る" => "五段・ラ行",
}.freeze

# Returns [pos, conj] or nil when the entry is not a target.
def classify(features, reading)
  f = features.split(",")
  case f[0]
  when "名詞"
    return nil unless NOUN_SUB.include?(f[1])
    ["名詞", "*"]
  when "動詞"
    return nil unless f[1] == "自立" && f[5] == "基本形"
    conj = f[4]
    conj = GODAN_BY_ENDING.fetch(reading[-1], conj) if conj == "五段動詞"
    conj = "サ変・−スル" if conj.start_with?("サ変")
    return nil if %w[文語 四段・タ行 ラ変].include?(conj)
    ["動詞", conj]
  when "形容詞"
    return nil unless f[1] == "自立" && f[5] == "基本形"
    ["形容詞", f[4]]
  end
end

# ---- load id.def ----
id_def = File.join(opts[:mozc_dir], "id.def")
abort "not found: #{id_def}" unless File.exist?(id_def)
features = {}
File.foreach(id_def, encoding: "UTF-8") do |line|
  id, feat = line.chomp.split(" ", 2)
  features[id.to_i] = feat
end

# ---- existing usage_dict ----
covered = Hash.new { |h, k| h[k] = [] } # reading => [surfaces]
if opts[:usage_dict] && File.exist?(opts[:usage_dict])
  File.foreach(opts[:usage_dict], encoding: "UTF-8") do |line|
    r, s, = line.chomp.split("\t")
    covered[r] << s if r && s
  end
  warn "usage_dict: #{covered.size} readings already covered"
else
  warn "usage_dict not given/found: nothing will be skipped"
end

# ---- scan Mozc dictionary ----
files = Dir[File.join(opts[:mozc_dir], "dictionary0*.txt")].sort
abort "no dictionary0*.txt in #{opts[:mozc_dir]}" if files.empty?

# Mozc contains many "word + suffix" compounds (講座内 / 口座内, 事故後 ...).
# Their homophone choice is the same as the base word's, so drop them when
# the stem is itself a dictionary word.
SUFFIXES = %w[内 中 等 用 後 前 時 者 性 化 上 外 間 費 料 部 側 式 型 版 系 権 率 額 店 感 面 名 欄 案 日 毎 別 製 風 調 達 方 際 込 済].to_set
all_surfaces = Set.new
files.each do |path|
  File.foreach(path, encoding: "UTF-8") { |line| all_surfaces << line.split("\t", 6)[4]&.chomp }
end
def derived_compound?(surface, all_surfaces)
  surface.length >= 3 && SUFFIXES.include?(surface[-1]) && all_surfaces.include?(surface[0..-2])
end

groups = Hash.new { |h, k| h[k] = {} } # [reading,pos] => {surface => cost}
conj_of = {}                            # [reading,pos] => conj of the most common spelling
files.each do |path|
  File.foreach(path, encoding: "UTF-8") do |line|
    reading, lid, _rid, cost, surface = line.chomp.split("\t")
    next unless surface && reading.length >= 2
    next unless surface.match?(KANJI)
    next unless reading.match?(HIRAGANA_ONLY)
    # 4月 / 四月, 1番 / 一番: digit spellings are notation variants, not homophones.
    next if surface.match?(/[0-9０-９]/)
    # Phrases: an adverb or noun written in kana followed by a word
    # (たくさん生まれ, すべて言い) or two words joined by a particle
    # (今の時期, 目を留める). The base words form their own groups.
    next if surface.match?(/\A\p{Hiragana}{3,}/)
    next if surface.match?(/\p{Han}[のをがにへと]\p{Han}/)
    cls = classify(features[lid.to_i].to_s, reading)
    next unless cls
    if cls[0] == "名詞"
      next if derived_compound?(surface, all_surfaces)
      # Phrase fragments registered as nouns (気になっ, 木になる ...).
      next if surface.end_with?("っ") || surface.match?(/\p{Hiragana}{3,}\z/)
    end
    # Verbs/adjectives must end with the same kana as the reading; this drops
    # Mozc compounds such as "かっこいい曲" tagged as adjectives.
    next if cls[0] != "名詞" && surface[-1] != reading[-1]
    cost = cost.to_i
    next if cost > opts[:max_cost]
    key = [reading, cls[0]]
    cur = groups[key][surface]
    next unless cur.nil? || cost < cur
    groups[key][surface] = cost
    best = groups[key].values.min
    conj_of[key] = cls[1] if cost <= best
  end
end

# Okurigana / kana-mix variants (照りつける vs 照り付ける, ご存じ vs ご存知,
# 子供 vs 子ども) are spelling variants, not homophones. Treat X as a variant
# of Y when X can be produced from Y by writing some of Y's kanji in hiragana.
# Same reading is guaranteed, so we only need to compare spellings: each kanji
# may be written as hiragana, and each hiragana (okurigana) may be dropped
# (買取 / 買い取り, 行う / 行なう, 怖気づく / 怖じ気付く).
# Old and new forms of the same kanji (剝 / 剥, 頰 / 頬) are also variants.
ITAIJI = {
  "剝" => "剥", "頰" => "頬", "𠮟" => "叱", "塡" => "填", "摑" => "掴",
  "噓" => "嘘", "繫" => "繋", "蔣" => "蒋", "醬" => "醤", "屛" => "屏",
  "瘦" => "痩", "餠" => "餅", "攪" => "撹", "鷗" => "鴎", "吞" => "呑",
  "遙" => "遥", "禱" => "祷", "姸" => "妍", "揭" => "掲", "搔" => "掻",
}.freeze

# Katakana and hiragana spellings (カイワレ大根 / かいわれ大根) are variants.
def normalize_spelling(surface)
  surface.tr("ァ-ヶ", "ぁ-ゖ").gsub(Regexp.union(ITAIJI.keys), ITAIJI)
end

def variant_pattern(surface)
  body = surface.each_char.map do |ch|
    if ch.match?(KANJI)
      "(?:#{Regexp.escape(ch)}|\\p{Hiragana}+)"
    elsif ch.match?(/\p{Hiragana}/)
      "#{Regexp.escape(ch)}?"
    else
      Regexp.escape(ch)
    end
  end.join
  /\A#{body}\z/
end

def variant?(a, b)
  a = normalize_spelling(a)
  b = normalize_spelling(b)
  a == b || a.match?(variant_pattern(b)) || b.match?(variant_pattern(a))
end

# cands are sorted by cost, so the more common spelling is kept and the
# others are recorded under "variants".
def collapse_variants(cands)
  kept = []
  cands.each do |c|
    if (k = kept.find { |x| variant?(x["surface"], c["surface"]) })
      (k["variants"] ||= []) << c["surface"]
    else
      kept << c
    end
  end
  kept
end

# ---- filter & rank ----
out = []
skipped_covered = 0
skipped_variants = 0
groups.each do |(reading, pos), surfaces|
  conj = conj_of[[reading, pos]]
  next if surfaces.size < opts[:min_candidates]
  cands = surfaces.sort_by { |_, c| c }.map { |s, c| { "surface" => s, "cost" => c } }
  cands = collapse_variants(cands)
  if cands.size < opts[:min_candidates]
    skipped_variants += 1
    next
  end

  existing = covered.key?(reading) ? covered[reading] : []
  missing = cands.reject { |c| existing.include?(c["surface"]) }
  unless existing.empty?
    if !opts[:include_partial] || missing.empty?
      skipped_covered += 1
      next
    end
  end

  # Priority: how common the 2nd-best spelling is. If even the runner-up is
  # common, users really do have to choose.
  priority = cands[1]["cost"]
  out << {
    "reading" => reading, "pos" => pos, "conj" => conj,
    "priority" => priority, "candidates" => cands,
    "existing" => existing,
  }
end

out.sort_by! { |g| [g["priority"], g["reading"]] }
out = out.first(opts[:limit]) if opts[:limit]

FileUtils.mkdir_p(File.dirname(opts[:out]))
File.open(opts[:out], "w:UTF-8") { |f| out.each { |g| f.puts JSON.generate(g) } }

warn "groups written: #{out.size} -> #{opts[:out]}"
warn "  skipped (already in usage_dict): #{skipped_covered}"
warn "  skipped (only spelling variants): #{skipped_variants}"
warn "  spellings total: #{out.sum { |g| g["candidates"].size }}"
