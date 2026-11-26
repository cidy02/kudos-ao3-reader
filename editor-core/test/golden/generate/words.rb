# Word-count goldens (spec 3.6, OD3). Runs otwarchive's own WordCounter (lib/word_counter.rb, vendored unmodified
# under upstream/otwarchive, commit 452391b6) over the hand-written cases (words-cases.json), the cleaning corpus
# (corpus.json) and, when FIXTURES names it, the 510,000-character fixtures. Writes test/golden/words.golden.json, a
# platform-neutral map from case id to AO3's count that the JS and Swift counters are both tested against.
#
#   node test/golden/make-words-cases.ts
#   cd test/golden/generate && bundle exec ruby words.rb   # FIXTURES=$TMPDIR/kudos-words-fixtures.json for the fixtures
Encoding.default_external = Encoding::UTF_8
require "bundler/setup"
require "json"
require "yaml"
require "nokogiri"

VENDOR = File.expand_path("upstream/otwarchive", __dir__)
OUT_DIR = File.expand_path("..", __dir__)

# Stand-in for otwarchive's ArchiveConfig: the real config/config.yml, read as is.
class ArchiveConfigStub
  def initialize(yaml) = @yaml = yaml

  def method_missing(name, *args)
    key = name.to_s
    @yaml.key?(key) ? @yaml[key] : super
  end

  def respond_to_missing?(name, include_private = false) = @yaml.key?(name.to_s) || super
end
ArchiveConfig = ArchiveConfigStub.new(YAML.safe_load_file(File.join(VENDOR, "config.yml"), aliases: true))

require File.join(VENDOR, "lib/word_counter.rb")

def count(input)
  WordCounter.new(input).count
rescue StandardError => e
  "!#{e.class.name}"
end

sets = [File.join(OUT_DIR, "words-cases.json"), File.join(OUT_DIR, "corpus.json")]
sets << ENV["FIXTURES"] if ENV["FIXTURES"] && !ENV["FIXTURES"].empty?
words = {}
sets.each do |path|
  JSON.parse(File.read(path))["cases"].each do |c|
    raise "duplicate case id #{c['id']}" if words.key?(c["id"])
    words[c["id"]] = count(c["input"])
  end
end

# What AO3 shows: it sanitizes a field before saving it (ApplicationController#sanitize_params) and counts what it
# stored. So also count each corpus case's cleaned content, from part 1's goldens (sanitize.golden.json).
stored = {}
JSON.parse(File.read(File.join(OUT_DIR, "sanitize.golden.json")))["cases"].each do |c|
  html = c.dig("content", "html")
  stored[c["id"]] = count(html) if html
end

golden = {
  "generator" => {
    "otwarchive" => "452391b648f2fb06b55c36133812449747634504",
    "ruby" => RUBY_VERSION, "nokogiri" => Nokogiri::VERSION,
    "scripts" => ArchiveConfig.CHARACTER_COUNT_SCRIPTS,
    "sets" => sets.map { |s| File.basename(s) },
  },
  "words" => words,
  "stored" => stored,
}
File.write(File.join(OUT_DIR, "words.golden.json"), JSON.pretty_generate(golden) + "\n")
puts "wrote words.golden.json (#{words.size} counts, #{stored.size} of stored content)"
