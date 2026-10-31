# frozen_string_literal: true

require "json"
require "set"
require "open3"
require "tmpdir"
require "timeout"

module UsageGen
  ROOT = File.expand_path("..", __dir__)

  module_function

  # ---------- JSONL helpers ----------

  def read_jsonl(path)
    return [] unless File.exist?(path)
    File.foreach(path, encoding: "UTF-8").filter_map do |line|
      line = line.strip
      next if line.empty?
      JSON.parse(line)
    end
  end

  def append_jsonl(path, obj, mutex = nil)
    line = JSON.generate(obj) + "\n"
    if mutex
      mutex.synchronize { File.write(path, line, mode: "a", encoding: "UTF-8") }
    else
      File.write(path, line, mode: "a", encoding: "UTF-8")
    end
  end

  def group_key(g)
    "#{g["reading"]}\t#{g["pos"]}\t#{g["conj"]}"
  end

  def prompt_file(name)
    File.read(File.join(ROOT, "prompts", name), encoding: "UTF-8")
  end

  # ---------- claude -p wrapper ----------
  #
  # Calls the Claude Code CLI in print mode and returns the parsed object.
  # - Runs in an empty temp directory so no project CLAUDE.md / .mcp.json /
  #   .claude/settings.json is picked up.
  # - Replaces the system prompt and disables all tools: this is a pure
  #   text-in / JSON-out call.
  # - Set CLAUDE_BARE=1 (with ANTHROPIC_API_KEY) to also skip user-level
  #   hooks, plugins and memory via --bare.
  # - Set CLAUDE_API_KEY_HELPER to a command that prints the API key
  #   (e.g. `op read op://...`); it is passed as apiKeyHelper.
  class ClaudeCLI
    class Error < StandardError; end

    attr_reader :total_cost

    def initialize(model:, timeout: 300, retries: 3, bin: ENV.fetch("CLAUDE_BIN", "claude"))
      @model = model
      @timeout = timeout
      @retries = retries
      @bin = bin
      @total_cost = 0.0
      @cost_mutex = Mutex.new
    end

    def call(system:, prompt:, schema:)
      attempt = 0
      begin
        attempt += 1
        run_once(system: system, prompt: prompt, schema: schema)
      rescue Error, Timeout::Error, JSON::ParserError => e
        raise Error, "#{e.class}: #{e.message}" if attempt > @retries
        wait = 5 * attempt
        warn "  ! #{e.message.lines.first&.strip} (retry #{attempt}/#{@retries} in #{wait}s)"
        sleep wait
        retry
      end
    end

    private

    def build_cmd(system:, schema:)
      cmd = [@bin]
      cmd << "--bare" if ENV["CLAUDE_BARE"] == "1"
      cmd += [
        "-p",
        "--model", @model,
        "--output-format", "json",
        "--json-schema", JSON.generate(schema),
        "--system-prompt", system,
        "--tools", "",
        "--strict-mcp-config",
        "--disable-slash-commands",
        "--no-session-persistence",
      ]
      if (helper = ENV["CLAUDE_API_KEY_HELPER"])
        cmd += ["--settings", JSON.generate("apiKeyHelper" => helper)]
      end
      if (budget = ENV["CLAUDE_MAX_BUDGET_USD"])
        cmd += ["--max-budget-usd", budget]
      end
      cmd
    end

    def run_once(system:, prompt:, schema:)
      cmd = build_cmd(system: system, schema: schema)
      out = err = status = nil
      Dir.mktmpdir("usagegen") do |dir|
        Timeout.timeout(@timeout) do
          # The prompt goes through stdin so long batches never hit ARG_MAX.
          out, err, status = Open3.capture3(*cmd, stdin_data: prompt, chdir: dir)
        end
      end

      data = begin
        JSON.parse(out)
      rescue JSON::ParserError
        raise Error, "non-JSON output (exit #{status&.exitstatus}): #{(out.to_s + err.to_s)[0, 300]}"
      end

      if (cost = data["total_cost_usd"])
        @cost_mutex.synchronize { @total_cost += cost.to_f }
      end

      if data["is_error"] || !status&.success?
        raise Error, "claude error (exit #{status&.exitstatus}): #{data["result"].to_s[0, 300]}"
      end

      obj = data["structured_output"]
      obj ||= extract_json(data["result"].to_s)
      raise Error, "no structured_output in response" unless obj.is_a?(Hash)
      obj
    end

    # Fallback when structured_output is absent: pull the first JSON object
    # out of the text result.
    def extract_json(text)
      text = text[/```(?:json)?\s*(.*?)```/m, 1] || text
      start = text.index("{")
      stop = text.rindex("}")
      return nil unless start && stop && stop > start
      JSON.parse(text[start..stop])
    rescue JSON::ParserError
      nil
    end
  end

  # ---------- simple parallel runner ----------

  def run_parallel(items, jobs)
    queue = Queue.new
    items.each { |i| queue << i }
    jobs.times.map do
      Thread.new do
        loop do
          item = begin
            queue.pop(true)
          rescue ThreadError
            break
          end
          yield item
        end
      end
    end.each(&:join)
  end
end
