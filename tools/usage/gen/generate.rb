#!/usr/bin/env ruby
# frozen_string_literal: true

# Generate usage notes for each homophone group with `claude -p`.
#
#   ruby generate.rb --limit 50              # pilot
#   ruby generate.rb --jobs 4                # everything, 4 parallel calls
#   ruby generate.rb --dry-run --limit 10    # show the prompt/command only
#
# Resumable: groups already in the output file are skipped, so you can
# Ctrl-C and run the same command again.

require "optparse"
require "fileutils"
require_relative "lib/common"

opts = {
  in: "work/groups.jsonl",
  out: "work/generated.jsonl",
  model: ENV.fetch("GEN_MODEL", "haiku"),
  batch: 10,
  jobs: 2,
  limit: nil,
  dry_run: false,
}
OptionParser.new do |o|
  o.banner = "Usage: ruby generate.rb [options]"
  o.on("--in FILE", "Groups JSONL from extract_groups.rb") { |v| opts[:in] = v }
  o.on("--out FILE", "Output JSONL (appended, resumable)") { |v| opts[:out] = v }
  o.on("--model NAME", "Model alias or full name (default: haiku)") { |v| opts[:model] = v }
  o.on("--batch N", Integer, "Groups per claude -p call (default 10)") { |v| opts[:batch] = v }
  o.on("-j", "--jobs N", Integer, "Parallel calls (default 2)") { |v| opts[:jobs] = v }
  o.on("--limit N", Integer, "Process only the first N groups (after skipping done ones)") { |v| opts[:limit] = v }
  o.on("--dry-run", "Print the first prompt and exit") { opts[:dry_run] = true }
end.parse!

SCHEMA = {
  "type" => "object",
  "properties" => {
    "groups" => {
      "type" => "array",
      "items" => {
        "type" => "object",
        "properties" => {
          "id" => { "type" => "integer" },
          "entries" => {
            "type" => "array",
            "items" => {
              "type" => "object",
              "properties" => {
                "surface" => { "type" => "string" },
                "include" => { "type" => "boolean" },
                "definition" => { "type" => "string" },
                "note" => { "type" => "string" },
              },
              "required" => %w[surface include definition note],
            },
          },
        },
        "required" => %w[id entries],
      },
    },
  },
  "required" => ["groups"],
}.freeze

groups = UsageGen.read_jsonl(opts[:in])
abort "no groups in #{opts[:in]} (run extract_groups.rb first)" if groups.empty?

done = UsageGen.read_jsonl(opts[:out]).map { |g| UsageGen.group_key(g) }.to_set
todo = groups.reject { |g| done.include?(UsageGen.group_key(g)) }
todo = todo.first(opts[:limit]) if opts[:limit]
warn "groups: #{groups.size} total, #{done.size} done, #{todo.size} to process"
exit if todo.empty?

system_prompt = UsageGen.prompt_file("generate_system.md")

def build_prompt(batch)
  payload = batch.each_with_index.map do |g, i|
    { "id" => i, "reading" => g["reading"], "pos" => g["pos"],
      "candidates" => g["candidates"].map { |c| c["surface"] } }
  end
  <<~PROMPT
    次のグループすべてについて、候補ごとの用例を作成してください。
    すべての候補を、入力と同じ表記で返してください。

    #{JSON.pretty_generate(payload)}
  PROMPT
end

batches = todo.each_slice(opts[:batch]).to_a

if opts[:dry_run]
  puts "=== system prompt (prompts/generate_system.md) ===", system_prompt
  puts "=== prompt (stdin) ===", build_prompt(batches.first)
  puts "=== command ==="
  puts "claude -p --model #{opts[:model]} --output-format json --json-schema '<schema>' " \
       "--system-prompt '<above>' --tools '' --strict-mcp-config --disable-slash-commands --no-session-persistence"
  exit
end

FileUtils.mkdir_p(File.dirname(opts[:out]))
claude = UsageGen::ClaudeCLI.new(model: opts[:model])
mutex = Mutex.new
progress = 0
failed = 0
started = Time.now

UsageGen.run_parallel(batches, opts[:jobs]) do |batch|
  begin
    res = claude.call(system: system_prompt, prompt: build_prompt(batch), schema: SCHEMA)
    by_id = (res["groups"] || []).to_h { |g| [g["id"], g["entries"]] }
    batch.each_with_index do |g, i|
      entries = by_id[i]
      expected = g["candidates"].map { |c| c["surface"] }
      got = entries&.map { |e| e["surface"] }
      unless entries && expected.sort == got.sort
        mutex.synchronize { failed += 1 }
        warn "  ! #{g["reading"]}: response did not match candidates (will retry next run)"
        next
      end
      UsageGen.append_jsonl(opts[:out], g.merge("entries" => entries, "gen_model" => opts[:model]), mutex)
    end
  rescue UsageGen::ClaudeCLI::Error => e
    mutex.synchronize { failed += batch.size }
    warn "  ! batch failed: #{e.message[0, 200]}"
  end
  mutex.synchronize do
    progress += batch.size
    warn format("[%d/%d] %.0fs  est. cost $%.3f", progress, todo.size, Time.now - started, claude.total_cost)
  end
end

warn "done. failed groups: #{failed} (re-run the same command to retry them)"
warn format("estimated cost reported by claude: $%.3f", claude.total_cost)
