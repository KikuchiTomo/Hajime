#!/usr/bin/env ruby
# frozen_string_literal: true

# Second pass: a stronger model reviews the generated notes.
#
#   ruby verify.rb                 # all generated groups, model: sonnet
#   ruby verify.rb --model opus    # stricter / slower
#
# Writes work/verified.jsonl (resumable). Each record keeps the original
# entries and adds verdict / issues / final entries.

require "optparse"
require "fileutils"
require_relative "lib/common"

opts = {
  in: "work/generated.jsonl",
  out: "work/verified.jsonl",
  model: ENV.fetch("VERIFY_MODEL", "sonnet"),
  batch: 10,
  jobs: 2,
  limit: nil,
}
OptionParser.new do |o|
  o.banner = "Usage: ruby verify.rb [options]"
  o.on("--in FILE") { |v| opts[:in] = v }
  o.on("--out FILE") { |v| opts[:out] = v }
  o.on("--model NAME", "default: sonnet") { |v| opts[:model] = v }
  o.on("--batch N", Integer) { |v| opts[:batch] = v }
  o.on("-j", "--jobs N", Integer) { |v| opts[:jobs] = v }
  o.on("--limit N", Integer) { |v| opts[:limit] = v }
end.parse!

ENTRY = {
  "type" => "object",
  "properties" => {
    "surface" => { "type" => "string" },
    "include" => { "type" => "boolean" },
    "definition" => { "type" => "string" },
  },
  "required" => %w[surface include definition],
}.freeze

SCHEMA = {
  "type" => "object",
  "properties" => {
    "groups" => {
      "type" => "array",
      "items" => {
        "type" => "object",
        "properties" => {
          "id" => { "type" => "integer" },
          "verdict" => { "type" => "string", "enum" => %w[ok fixed drop] },
          "issues" => { "type" => "string" },
          "entries" => { "type" => "array", "items" => ENTRY },
        },
        "required" => %w[id verdict issues entries],
      },
    },
  },
  "required" => ["groups"],
}.freeze

generated = UsageGen.read_jsonl(opts[:in])
abort "nothing in #{opts[:in]} (run generate.rb first)" if generated.empty?
done = UsageGen.read_jsonl(opts[:out]).map { |g| UsageGen.group_key(g) }.to_set
todo = generated.reject { |g| done.include?(UsageGen.group_key(g)) }
todo = todo.first(opts[:limit]) if opts[:limit]
warn "generated: #{generated.size}, verified: #{done.size}, to verify: #{todo.size}"
exit if todo.empty?

system_prompt = UsageGen.prompt_file("verify_system.md")

def build_prompt(batch)
  payload = batch.each_with_index.map do |g, i|
    { "id" => i, "reading" => g["reading"], "pos" => g["pos"],
      "entries" => g["entries"].map { |e| e.slice("surface", "include", "definition") } }
  end
  "次の用例を校閲してください。\n\n#{JSON.pretty_generate(payload)}\n"
end

FileUtils.mkdir_p(File.dirname(opts[:out]))
claude = UsageGen::ClaudeCLI.new(model: opts[:model])
mutex = Mutex.new
stats = Hash.new(0)
progress = 0

UsageGen.run_parallel(todo.each_slice(opts[:batch]).to_a, opts[:jobs]) do |batch|
  begin
    res = claude.call(system: system_prompt, prompt: build_prompt(batch), schema: SCHEMA)
    by_id = (res["groups"] || []).to_h { |g| [g["id"], g] }
    batch.each_with_index do |g, i|
      v = by_id[i]
      unless v && v["entries"].map { |e| e["surface"] }.sort == g["entries"].map { |e| e["surface"] }.sort
        mutex.synchronize { stats["failed"] += 1 }
        next
      end
      rec = g.merge("verdict" => v["verdict"], "issues" => v["issues"],
                    "final" => v["entries"], "verify_model" => opts[:model])
      UsageGen.append_jsonl(opts[:out], rec, mutex)
      mutex.synchronize { stats[v["verdict"]] += 1 }
    end
  rescue UsageGen::ClaudeCLI::Error => e
    mutex.synchronize { stats["failed"] += batch.size }
    warn "  ! batch failed: #{e.message[0, 200]}"
  end
  mutex.synchronize do
    progress += batch.size
    warn format("[%d/%d] %s  est. cost $%.3f", progress, todo.size, stats.to_h, claude.total_cost)
  end
end

warn "done: #{stats.to_h}"
