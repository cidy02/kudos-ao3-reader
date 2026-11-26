# Golden generator (spec 6.10). Loads otwarchive's own HtmlCleaner#sanitize_value, ParagraphMaker and the
# sanitizer transformers (vendored unmodified under vendor/otwarchive, commit 452391b6) and runs every
# field variant over test/golden/corpus.json. Writes test/golden/sanitize.golden.json.
#
#   cd editor-core/test/golden/generate && bundle install && bundle exec ruby generate.rb
#
# Environment overrides (used for ad-hoc checks): CORPUS=<path to corpus json>, GOLDEN_OUT=<output path>.
Encoding.default_external = Encoding::UTF_8 # do not depend on the caller's locale
require "bundler/setup"
require "json"
require "yaml"
require "set"
require "uri"
require "cgi"
require "sanitize"
require "nokogiri"
require "active_support"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/module/delegation"

VENDOR = File.expand_path("vendor/otwarchive", __dir__)
OUT_DIR = File.expand_path("..", __dir__)

# Stand-in for otwarchive's ArchiveConfig: the real config/config.yml, read as is.
# APP_URL is the one value production overrides in its local.yml; the JS port defaults to the same.
class ArchiveConfigStub
  def initialize(yaml) = @yaml = yaml

  def method_missing(name, *args)
    key = name.to_s
    return "https://archiveofourown.org" if key == "APP_URL"
    @yaml.key?(key) ? @yaml[key] : super
  end

  def respond_to_missing?(name, include_private = false) = @yaml.key?(name.to_s) || super
end
ArchiveConfig = ArchiveConfigStub.new(YAML.safe_load_file(File.join(VENDOR, "config.yml"), aliases: true))

require File.join(VENDOR, "config/initializers/gem-plugin_config/sanitizer_config.rb")
require File.join(VENDOR, "lib/paragraph_maker.rb")
require File.join(VENDOR, "lib/otw_sanitize/user_class_sanitizer.rb")
require File.join(VENDOR, "lib/otw_sanitize/embed_sanitizer.rb")
require File.join(VENDOR, "lib/otw_sanitize/media_sanitizer.rb")
require File.join(VENDOR, "lib/html_cleaner.rb")

class Cleaner
  include HtmlCleaner
end

def run(cleaner, field, value)
  { "html" => cleaner.sanitize_value(field, value) }
rescue StandardError => e
  { "error" => e.class.name }
end

# The ParagraphMaker stage on its own, as sanitize_value feeds it: strip!, fix_bad_characters, add_paragraphs_to_text.
def stage_paragraphs(cleaner, value)
  v = value.dup
  v.strip!
  cleaner.add_paragraphs_to_text(cleaner.fix_bad_characters(v))
rescue StandardError => e
  "!#{e.class.name}"
end

cleaner = Cleaner.new
corpus = JSON.parse(File.read(ENV["CORPUS"] || File.join(OUT_DIR, "corpus.json")))
cases = corpus["cases"].map do |c|
  input = c["input"]
  entry = { "id" => c["id"], "paragraphs" => input.strip.empty? ? "" : stage_paragraphs(cleaner, input) }
  %w[content notes summary].each { |variant| entry[variant] = run(cleaner, variant, input) }
  endnotes = run(cleaner, "endnotes", input)
  raise "endnotes differs from notes for #{c['id']}" unless endnotes == entry["notes"]
  entry
end

golden = {
  "generator" => {
    "otwarchive" => "452391b648f2fb06b55c36133812449747634504",
    "ruby" => RUBY_VERSION, "sanitize" => Sanitize::VERSION, "nokogiri" => Nokogiri::VERSION,
    "appUrl" => ArchiveConfig.APP_URL
  },
  "cases" => cases
}
File.write(ENV["GOLDEN_OUT"] || File.join(OUT_DIR, "sanitize.golden.json"), JSON.pretty_generate(golden) + "\n")
puts "wrote #{cases.length} cases"
