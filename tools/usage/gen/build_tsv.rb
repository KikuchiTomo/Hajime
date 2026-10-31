#!/usr/bin/env ruby
# frozen_string_literal: true

# Turn generated / verified JSONL into usage_dict.txt-compatible TSV:
#   reading <TAB> surface <TAB> conjugation <TAB> definition
#
#   ruby build_tsv.rb                         # from work/verified.jsonl
#   ruby build_tsv.rb --from work/generated.jsonl   # skip verification
#   ruby build_tsv.rb --merge data/usage_dict.txt   # also merge the original
#
# Also writes work/review.tsv with everything the verifier changed or
# dropped, so a human can skim just those.

require "optparse"
require "fileutils"
require_relative "lib/common"

opts = {
  from: "work/verified.jsonl",
  out: "out/usage_dict_extra.tsv",
  review: "work/review.tsv",
  merge: nil,
  keep_dropped: false,
}
OptionParser.new do |o|
  o.banner = "Usage: ruby build_tsv.rb [options]"
  o.on("--from FILE", "verified.jsonl or generated.jsonl") { |v| opts[:from] = v }
  o.on("-o", "--out FILE") { |v| opts[:out] = v }
  o.on("--review FILE") { |v| opts[:review] = v }
  o.on("--merge FILE", "Merge with an existing usage_dict.txt") { |v| opts[:merge] = v }
  o.on("--keep-dropped", "Keep groups the verifier marked as drop") { opts[:keep_dropped] = true }
  o.on("--keep-single", "Keep groups with only one included spelling") { opts[:keep_single] = true }
end.parse!

records = UsageGen.read_jsonl(opts[:from])
abort "nothing in #{opts[:from]}" if records.empty?

def clean(text)
  text.to_s.tr("\t", " ").gsub(/\r?\n/, "\\n").strip
end

rows = []
review = []
single = 0
records.each do |g|
  verdict = g["verdict"]
  entries = g["final"] || g["entries"]
  if verdict && verdict != "ok"
    g["entries"].each do |orig|
      fin = entries.find { |e| e["surface"] == orig["surface"] } || {}
      review << [verdict, g["reading"], orig["surface"], clean(orig["definition"]),
                 fin["include"] ? clean(fin["definition"]) : "(載せない)", clean(g["issues"])]
    end
  end
  next if verdict == "drop" && !opts[:keep_dropped]

  kept = entries.select { |e| e["include"] && !clean(e["definition"]).empty? }
  # With only one spelling left there is nothing to choose between.
  if kept.size < 2 && !opts[:keep_single]
    single += 1
    next
  end
  kept.each do |e|
    rows << [g["reading"], e["surface"], g["conj"] || "*", clean(e["definition"])]
  end
end
warn "skipped groups with fewer than 2 entries: #{single}" if single.positive?

if opts[:merge]
  existing = File.readlines(opts[:merge], chomp: true, encoding: "UTF-8").map { |l| l.split("\t", 4) }
  have = existing.map { |r| r[0, 2] }.to_set
  rows = existing + rows.reject { |r| have.include?(r[0, 2]) }
end

rows.uniq! { |r| r[0, 2] }
rows.sort_by! { |r| [r[0], r[1]] }

FileUtils.mkdir_p(File.dirname(opts[:out]))
File.write(opts[:out], rows.map { |r| r.join("\t") }.join("\n") + "\n", encoding: "UTF-8")
warn "wrote #{rows.size} rows (#{rows.map(&:first).uniq.size} readings) -> #{opts[:out]}"

unless review.empty?
  FileUtils.mkdir_p(File.dirname(opts[:review]))
  header = %w[verdict reading surface before after issues].join("\t")
  File.write(opts[:review], ([header] + review.map { |r| r.join("\t") }).join("\n") + "\n", encoding: "UTF-8")
  warn "review list: #{review.size} rows -> #{opts[:review]}"
end
