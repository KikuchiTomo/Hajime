#!/usr/bin/env ruby
# frozen_string_literal: true

# Append the part of speech (品詞) to each row of a usage dictionary TSV.
#
#   ruby annotate_pos.rb --mozc-dir path/to/dictionary_oss data/usage/usage_dict_words.tsv ...
#
# Rows are "reading<TAB>surface<TAB>conjugation<TAB>description". The 5th
# column becomes the part of speech of the same reading and spelling in
# Mozc's dictionary (名詞, 動詞, 形容詞, 形容動詞, 副詞, ...), taken from the
# right id so that compounds get the part of speech of their last word
# (お化粧 is a noun, not a prefix; 委員長 is a noun, not a suffix). When Mozc has several entries, the one that
# agrees with the conjugation column (verbs and adjectives conjugate, the rest
# do not) wins, then words over affixes (愛 is a noun before a suffix), then
# the lowest cost. Rows
# that Mozc lacks fall back to the conjugation column; otherwise the column is
# left empty. Files are rewritten in place; comment lines are kept as they are.

require "optparse"

opts = { mozc_dir: "data" }
OptionParser.new do |o|
  o.banner = "Usage: ruby annotate_pos.rb [--mozc-dir DIR] FILE..."
  o.on("--mozc-dir DIR", "Directory with dictionary0*.txt and id.def") { |v| opts[:mozc_dir] = v }
end.parse!
abort "no input files" if ARGV.empty?

# id.def features ("名詞,形容動詞語幹,*,...") -> label shown in the candidate window.
# A compound (its left id differs from the right id) that ends with a suffix
# takes the part of speech the suffix makes (委員長 is a noun).
def label(features, compound)
  f = features.split(",")
  suffix = f[1] == "接尾" && !compound
  case f[0]
  when "名詞"
    return "接尾辞" if suffix

    case f[1]
    when "形容動詞語幹" then "形容動詞"
    when "代名詞" then "代名詞"
    else "名詞"
    end
  when "動詞" then suffix ? "接尾辞" : "動詞"
  when "形容詞" then suffix ? "接尾辞" : "形容詞"
  when "副詞" then "副詞"
  when "連体詞" then "連体詞"
  when "接続詞" then "接続詞"
  when "感動詞" then "感動詞"
  when "接頭詞" then "接頭辞"
  end
end

CONJUGATING = %w[動詞 形容詞].freeze
AFFIXES = %w[接頭辞 接尾辞].freeze

def conjugating?(conjugation)
  conjugation != "*" && !conjugation.empty?
end

def from_conjugation(conjugation)
  return "形容詞" if conjugation.start_with?("形容詞")
  return "動詞" if conjugating?(conjugation) && conjugation != "不変化型"

  nil
end

id_def = File.join(opts[:mozc_dir], "id.def")
abort "not found: #{id_def}" unless File.exist?(id_def)
features = {}
File.foreach(id_def, encoding: "UTF-8") do |line|
  id, feature = line.chomp.split(" ", 2)
  features[id.to_i] = feature.to_s
end

# "reading\tsurface" => [[label, cost], ...]
entries = Hash.new { |h, k| h[k] = [] }
files = Dir[File.join(opts[:mozc_dir], "dictionary0*.txt")].sort
abort "no dictionary0*.txt in #{opts[:mozc_dir]}" if files.empty?
files.each do |path|
  File.foreach(path, encoding: "UTF-8") do |line|
    reading, lid, rid, cost, surface = line.chomp.split("\t")
    next unless surface
    pos = label(features[rid.to_i].to_s, lid != rid)
    entries["#{reading}\t#{surface}"] << [pos, cost.to_i] if pos
  end
end

def best(candidates, conjugation)
  return nil if candidates.empty?

  agreeing = candidates.select { |pos, _| CONJUGATING.include?(pos) == conjugating?(conjugation) }
  (agreeing.empty? ? candidates : agreeing).min_by { |pos, cost| [AFFIXES.include?(pos) ? 1 : 0, cost] }[0]
end

ARGV.each do |path|
  counts = Hash.new(0)
  lines = File.readlines(path, chomp: true, encoding: "UTF-8").map do |line|
    next line if line.start_with?("#") || line.empty?

    fields = line.split("\t", -1)
    next line if fields.size < 4

    reading, surface, conjugation = fields
    pos = best(entries["#{reading}\t#{surface}"], conjugation) || from_conjugation(conjugation) || ""
    counts[pos.empty? ? "(なし)" : pos] += 1
    (fields[0, 4] + [pos]).join("\t")
  end
  File.write(path, lines.join("\n") + "\n")
  warn "#{path}: " + counts.sort_by { |_, n| -n }.map { |pos, n| "#{pos} #{n}" }.join(", ")
end
