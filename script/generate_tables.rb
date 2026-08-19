#!/usr/bin/env ruby

# Code in this file adapted from the mimemagic gem, released under the MIT License.
# Copyright (c) 2011 Daniel Mendler. Available at https://github.com/mimemagicrb/mimemagic.

require 'nokogiri'
require 'digest'
require 'open3'
require 'optparse'
require 'rbconfig'
require 'stringio'
require 'tempfile'

module TikaRegex
  # Apache Tika uses Java regex syntax, which has some differences from Ruby:
  # - (?s) flag in Java is a mode which makes . match newlines
  #   In Ruby, this is equivalent to the multiline flag
  # - Java uses double-escaped sequences like \\d, \\x00, \\u0041 in XML
  #   These need to be converted to Ruby's single-escaped format: \d, \x00, \u0041
  # - Naturally, some Java regex features are not supported in Ruby (e.g., variable-length lookbehinds)
  #
  # This method handles the conversion and gracefully returns nil for incompatible patterns.
  #
  # @param pattern [String] The Tika regex pattern string
  # @return [Regexp, nil] The compiled Ruby Regexp, or nil if the pattern is incompatible
  def self.to_ruby_regexp(pattern)
    return nil if pattern.nil? || pattern.empty?

    processed = pattern.dup
    flags = 0

    # Converting Java's (?s) dotall flag to Ruby's multiline
    if processed.include?('(?s)')
      processed = processed.gsub('(?s)', '')
      flags |= Regexp::MULTILINE
    end

    # Convert Java-style double-escaped sequences to Ruby single-escaped format
    # This is more complex than a simple gsub because we need to handle:
    # - \\xHH -> \xHH (hex byte)
    # - \\uHHHH -> \uHHHH (unicode)
    # - \\OOO -> \xHH (convert octal to hex to avoid backreference ambiguity in TruffleRuby)
    # - \\d, \\w, \\s, etc. -> \d, \w, \s (character classes)
    # - \\[, \\], \\{, \\}, etc. -> \[, \], \{, \} (literal characters)
    #
    # We process these specifically to avoid breaking the regex structure
    processed = processed.gsub(/\\\\(x[0-9a-fA-F]{2})/, '\\\\\1')     # \\xHH -> \xHH
                         .gsub(/\\\\(u[0-9a-fA-F]{4})/, '\\\\\1')     # \\uHHHH -> \uHHHH
                         .gsub(/\\\\([0-7]{1,3})/) { "\\x#{$1.to_i(8).to_s(16).rjust(2, '0')}" } # \\OOO -> \xHH (octal to hex so that TruffleRuby doesn't think it's a backreference)
                         .gsub(/\\\\([WDS])/i, '\\\\\1')              # \\d etc. -> \d
                         .gsub(/\\\\([farbentv])/, '\\\\\1')          # \\n etc. -> \n
                         .gsub(/\\\\([()\[\]{}|*+?.^$\\])/, '\\\\\1') # \\[ etc. -> \[

    # Force binary encoding to handle binary escape sequences like \xff
    processed = processed.force_encoding(Encoding::BINARY)

    Regexp.new(processed, flags).freeze
  end
end

module RubySource
  def self.string(value)
    source = value.b.dump.gsub(/(\\+)x([0-9a-f]{2})/i) do |escape|
      slashes = $1
      if slashes.length.odd?
        slashes[0...-1] + ('\\%03o' % $2.to_i(16))
      else
        escape
      end
    end
    source.tr!('"', '\'') unless source.match?(/[\\']/)
    source
  end

  def self.words(values)
    if values.all? { |value| safe_word?(value) }
      "%w(#{values.join(' ')})"
    else
      "[#{values.map { |value| string(value) }.join(', ')}]"
    end
  end

  def self.comment(value)
    value.gsub(/[\x00-\x1f\x7f]|\u0085|\u2028|\u2029/, " ")
  end

  def self.safe_word?(value)
    !value.empty? && value.each_byte.all? do |byte|
      byte > 0x20 && byte < 0x7f && byte != 0x28 && byte != 0x29 && byte != 0x5c
    end
  end
end

module MimeData
  TOKEN = "[!#$%&'*+\\-.^_`|~0-9A-Za-z]+".freeze
  TYPE = %r{\A#{TOKEN}/#{TOKEN}(?:;[ \t]*#{TOKEN}=#{TOKEN})*\z}.freeze
  EXTENSION = /\A[0-9A-Za-z][0-9A-Za-z.+_~-]*\z/.freeze
  OFFSET = /\A\d+(?::\d+)?\z/.freeze
  PRIORITY = /\A\d+\z/.freeze
  MAX_MAGIC_OFFSET = 64 * 1024
  MAX_MAGIC_RANGE_BYTES = 64 * 1024
  MAX_MAGIC_PRIORITY = 100

  def self.type(value, source)
    if value&.match?(/[\x00-\x08\x0A-\x1F\x7F]/)
      raise ArgumentError, "Invalid MIME type in #{source}: #{value.inspect}"
    end

    normalized = value&.strip
    unless normalized&.match?(TYPE)
      raise ArgumentError, "Invalid MIME type in #{source}: #{value.inspect}"
    end

    normalized
  end

  def self.extension(value, source)
    unless value&.match?(EXTENSION)
      raise ArgumentError, "Invalid extension in #{source}: #{value.inspect}"
    end

    value.downcase
  end

  def self.offset(value, source)
    maximum_length = "#{MAX_MAGIC_OFFSET}:#{MAX_MAGIC_OFFSET}".bytesize
    unless value && value.bytesize <= maximum_length && value.match?(OFFSET)
      raise ArgumentError, "Invalid magic offset in #{source}: #{value.inspect}"
    end

    bounds = value.split(":").map { |bound| Integer(bound, 10) }
    if bounds.any? { |bound| bound > MAX_MAGIC_OFFSET }
      raise ArgumentError, "Magic offset exceeds #{MAX_MAGIC_OFFSET} in #{source}: #{value.inspect}"
    end
    if bounds.size == 2 && bounds.first > bounds.last
      raise ArgumentError, "Descending magic offset in #{source}: #{value.inspect}"
    end
    if bounds.size == 2 && bounds.last - bounds.first + 1 > MAX_MAGIC_RANGE_BYTES
      raise ArgumentError, "Magic range exceeds #{MAX_MAGIC_RANGE_BYTES} bytes in #{source}: #{value.inspect}"
    end

    bounds.size == 2 ? bounds[0]..bounds[1] : bounds[0]
  end

  def self.priority(value, source)
    unless value && value.bytesize <= MAX_MAGIC_PRIORITY.to_s.bytesize && value.match?(PRIORITY)
      raise ArgumentError, "Invalid magic priority in #{source}: #{value.inspect}"
    end

    priority = Integer(value, 10)
    if priority > MAX_MAGIC_PRIORITY
      raise ArgumentError, "Magic priority exceeds #{MAX_MAGIC_PRIORITY} in #{source}: #{value.inspect}"
    end

    priority
  end
end

class UnsupportedRules
  # Tika currently contains 58 unsupported XML rules. Their pretty-printed warnings
  # span 112 physical lines, so pin the canonical rule set rather than stderr layout.
  EXPECTED_COUNT = 58
  EXPECTED_SHA256 = "15d595d20bca116234fda6893b8fceb1533fcbd542d425a6d609d2efcb51b582"

  def initialize
    @signatures = []
  end

  def count
    @signatures.size
  end

  def skip(kind, mime_type, element, message)
    @signatures << [kind, mime_type, canonical_element(element)].inspect
    warn message
  end

  def verify!
    return if count.zero?

    digest = Digest::SHA256.hexdigest(@signatures.sort.join("\0"))
    return if count == EXPECTED_COUNT && digest == EXPECTED_SHA256

    raise ArgumentError,
      "Unsupported magic rules changed: expected #{EXPECTED_COUNT} " \
      "(sha256 #{EXPECTED_SHA256}), got #{count} (sha256 #{digest})"
  end

  private
    def canonical_element(element)
      attributes = element.attribute_nodes.sort_by(&:name).map { |attribute| [attribute.name, attribute.value] }
      children = element.element_children.map { |child| canonical_element(child) }
      [element.name, attributes, children]
    end
end

class BinaryString
  def initialize(string)
    @string = string
  end

  def inspect
    "b[#{RubySource.string(@string)}]"
  end
end

class RegexString
  def initialize(pattern)
    @pattern = pattern
  end

  def inspect
    regexp = TikaRegex.to_ruby_regexp(@pattern)
    if regexp
      "Regexp.new(#{regexp.source.b.dump}.b, #{regexp.options}).freeze"
    else
      "nil"
    end
  end
end

def str2int(s)
  return s.to_i(16) if s[0..1].downcase == '0x'
  return s.to_i(8) if s[0..0].downcase == '0'
  s.to_i(10)
end

ESCAPED_CHARACTERS = {
  'a' => "\a",
  'b' => "\b",
  'e' => "\e",
  'f' => "\f",
  'n' => "\n",
  'r' => "\r",
  's' => " ",
  't' => "\t",
  'v' => "\v",
}.freeze

def decode_string_escape(escape)
  case escape
  when /\Ax([0-9a-f]{1,2})\z/i
    $1.to_i(16).chr
  when /\A0?([0-7]{1,3})\z/
    $1.to_i(8).chr
  else
    ESCAPED_CHARACTERS.fetch(escape, escape)
  end
end

def binary_strings(object)
  case object
  when Array
    object.map { |o| binary_strings(o) }
  when String
    BinaryString.new(object)
  when RegexString
    object
  when Numeric, Range, nil
    object
  else
    raise TypeError, "unexpected #{object.class}"
  end
end

WELL_KNOWN_REGEX_TYPES = %w(
  application/x-bzip2
  text/html
  application/vnd.java.hprof
  application/vnd.java.hprof.text
)

def get_matches(mime_type, parent, unsupported_rules)
  parent.elements.map {|match|
    children = get_matches(mime_type, match, unsupported_rules)

    type = match['type']
    value = match['value']
    offset = match['offset'] || '0'
    offset = MimeData.offset(offset, mime_type)

    mask = match['mask']

    # We only support masks of whole bytes against a string type
    if mask && (!mask.match?(/\A0x(FF|00)*\z/) || type != 'string')
      unsupported_rules.skip "mask", mime_type, match, "#{mime_type}: unsupported mask #{match.to_s}"
      next nil
    end

    case type
      when 'unicodeLE', 'unicodeBE' # Unicode string types (UTF-16 Little/Big Endian)
        value.gsub!(/\A0x([0-9a-f]+)\z/i) { [$1].pack('H*') }
        encoding = type == 'unicodeLE' ? Encoding::UTF_16LE : Encoding::UTF_16BE
        value = value.encode(encoding).force_encoding(Encoding::BINARY)
    when 'regex'
      unless WELL_KNOWN_REGEX_TYPES.include?(mime_type)
        unsupported_rules.skip "regex", mime_type, match,
          "#{mime_type}: unsupported #{type} match: #{match.to_s}"
        next nil
      end

      value = RegexString.new(value)
    when 'string', 'stringignorecase'
      value.gsub!(/\A0x([0-9a-f]+)\z/i) { [$1].pack('H*') }
      value.gsub!(/\\(x[\dA-Fa-f]{1,2}|0\d{1,3}|\d{1,3}|.)/) { decode_string_escape($1) }

      if mask
        segments = []
        mask.scan(/(?:FF)+/) do
          match = $~
          match_offset = match.offset(0)
          mask_offset = (match_offset[0] - 2) / 2
          mask_length = (match_offset[1] - match_offset[0]) / 2
          segments << [mask_offset, mask_length]
        end

        chain = children
        segments.reverse_each do |(mask_offset, mask_length)|
          masked_value = value[mask_offset, mask_length]
          if chain.empty?
            chain = [[mask_offset, masked_value]]
          else
            chain = [[mask_offset, masked_value, chain]]
          end
        end
        next chain[0]
      end
    when 'big16'
      value = str2int(value)
      value = ((value >> 8).chr + (value & 0xFF).chr)
    when 'big32'
      value = str2int(value)
      value = (((value >> 24) & 0xFF).chr + ((value >> 16) & 0xFF).chr + ((value >> 8) & 0xFF).chr + (value & 0xFF).chr)
    when 'little16'
      value = str2int(value)
      value = ((value & 0xFF).chr + (value >> 8).chr)
    when 'little32'
      value = str2int(value)
      value = ((value & 0xFF).chr + ((value >> 8) & 0xFF).chr + ((value >> 16) & 0xFF).chr + ((value >> 24) & 0xFF).chr)
    when 'host16' # use little endian
      value = str2int(value)
      value = ((value & 0xFF).chr + (value >> 8).chr)
    when 'host32' # use little endian
      value = str2int(value)
      value = ((value & 0xFF).chr + ((value >> 8) & 0xFF).chr + ((value >> 16) & 0xFF).chr + ((value >> 24) & 0xFF).chr)
    when 'byte'
      value = str2int(value)
      value = value.chr
    when nil
      nil
    else
      unsupported_rules.skip "type", mime_type, match,
        "#{mime_type}: unsupported #{type} match: #{match.to_s}"
      next nil
    end

    children.empty? ? [offset, value] : [offset, value, children]
  }.compact
end

options = {}
option_parser = OptionParser.new do |parser|
  parser.banner = "Usage: #{$0} [--output path/to/tables.rb] path/to/data.xml [...]"
  parser.on("-o", "--output PATH", "Atomically write generated Ruby to PATH") do |path|
    options[:output] = path
  end
end
option_parser.parse!(ARGV)
abort option_parser.to_s if ARGV.empty?

TYPE_RENAMES = {
  "image/bmp;format=compressed" => "image/bmp",
}.freeze

# Marcel registers stricter, bounded HTML and XHTML rules at runtime. Keeping Tika's broad
# generated rules would make `require "marcel/magic"` alone retain the unsafe legacy matches.
RUNTIME_DEFINED_MAGIC_TYPES = %w(
  application/xhtml+xml
  text/html
).freeze

extensions = {}
types = {}
magics = []
unsupported_rules = UnsupportedRules.new

ARGV.each do |path|
  doc = File.open(path, "rb") do |file|
    Nokogiri::XML(file) { |config| config.strict.nonet }
  end
  unless doc.root&.name == "mime-info"
    raise ArgumentError, "Expected mime-info root in #{path}"
  end

  (doc/'mime-info/mime-type').each do |mime|
    comments = Hash[*(mime/'_comment').map {|comment| [comment['xml:lang'], comment.inner_text] }.flatten]
    type = MimeData.type(mime['type'], path)
    type = TYPE_RENAMES[type] || type

    subclass = (mime/'sub-class-of').map { |element| MimeData.type(element['type'], path) }
    exts = (mime/'glob').map do |element|
      if element['pattern'] =~ /^\*\.([^\[\]]+)$/
        MimeData.extension($1, path)
      end
    end.compact
    unless RUNTIME_DEFINED_MAGIC_TYPES.include?(type)
      (mime/'magic').each do |magic|
        priority = MimeData.priority(magic['priority'] || '50', type)
        matches = get_matches(type, magic, unsupported_rules)
        magics << [priority, type, matches]
      end
    end
    if !exts.empty?
      exts.each{|x|
        extensions[x] = type if !extensions.include?(x)
      }
      types[type] = [exts,subclass,comments[nil]]
    end
  end
end

magics = magics.each_with_index.sort_by do |(priority, type), source_index|
  [ -priority, type, source_index ]
end.map(&:first)

common_types = [
  "image/jpeg",                                                                # .jpg
  "image/png",                                                                 # .png
  "image/gif",                                                                 # .gif
  "image/tiff",                                                                # .tiff
  "image/bmp",                                                                 # .bmp
  "image/vnd.adobe.photoshop",                                                 # .psd
  "image/webp",                                                                # .webp
  "text/html",                                                                 # .html
  "image/svg+xml",                                                             # .svg

  "video/x-msvideo",                                                           # .avi
  "video/x-ms-wmv",                                                            # .wmv
  "video/mp4",                                                                 # .mp4, .m4v
  "audio/mp4",                                                                 # .m4a
  "video/quicktime",                                                           # .mov
  "video/mpeg",                                                                # .mpeg
  "video/ogg",                                                                 # .ogv
  "video/webm",                                                                # .webm
  "video/x-matroska",                                                          # .mkv
  "video/x-flv",                                                               # .flv

  "audio/mpeg",                                                                # .mp3
  "audio/x-wav",                                                               # .wav
  "audio/aac",                                                                 # .aac
  "audio/flac",                                                                # .flac
  "audio/ogg",                                                                 # .ogg

  "application/pdf",                                                           # .pdf
  "application/msword",                                                        # .doc
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document",   # .docx
  "application/vnd.ms-powerpoint",                                             # .pps
  "application/vnd.openxmlformats-officedocument.presentationml.slideshow",    # .ppsx
  "application/vnd.openxmlformats-officedocument.presentationml.presentation", # .pptx
  "application/vnd.ms-excel",                                                  # .xls
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",         # .xlsx
]

common_magics = common_types.map do |common_type|
  magics.find { |_, type, _| type == common_type }
end

magics = (common_magics.compact + magics).uniq

def emit_tables(output, extensions, types, magics)
  output.puts "# frozen_string_literal: true"
  output.puts ""
  output.puts "# This file is auto-generated. Instead of editing this file, please"
  output.puts "# add MIMEs to data/custom.xml or the definitions files under lib/marcel."
  output.puts ""
  output.puts "module Marcel"
  output.puts "  # @private"
  output.puts "  # :nodoc:"
  output.puts "  EXTENSIONS = {"
  extensions.keys.sort.each do |key|
    output.puts "    #{RubySource.string(key.strip)} => #{RubySource.string(extensions[key])},"
  end
  output.puts "  }"
  output.puts "  # @private"
  output.puts "  # :nodoc:"
  output.puts "  TYPE_EXTS = {"
  types.keys.sort.each do |key|
    exts = types[key][0]
    comment = types[key][2]
    comment = " # #{RubySource.comment(comment)}" if comment
    output.puts "    #{RubySource.string(key.strip)} => #{RubySource.words(exts)},#{comment}"
  end
  output.puts "  }"
  output.puts "  TYPE_PARENTS = {"
  types.keys.sort.each do |key|
    parents = types[key][1].sort
    unless parents.empty?
      output.puts "    #{RubySource.string(key.strip)} => #{RubySource.words(parents)},"
    end
  end
  output.puts "  }"
  output.puts "  b = Hash.new { |h, k| h[k] = k.b.freeze }"
  output.puts "  # @private"
  output.puts "  # :nodoc:"
  output.puts "  MAGIC = ["
  magics.each do |priority, type, matches|
    next if matches.nil? || matches.empty?

    output.puts "    [#{RubySource.string(type.strip)}, #{binary_strings(matches).inspect}],"
  end
  output.puts "  ]"
  output.puts "end"
end

def write_tables(output_path, contents)
  return $stdout.write(contents) unless output_path

  destination = File.expand_path(output_path)
  directory = File.dirname(destination)
  mode = File.exist?(destination) ? File.stat(destination).mode & 0o777 : 0o644

  Tempfile.create([File.basename(destination), ".tmp"], directory) do |temporary|
    temporary.binmode
    temporary.write(contents)
    temporary.flush
    temporary.fsync
    temporary.close

    syntax_output, status = Open3.capture2e(RbConfig.ruby, "-c", temporary.path)
    raise "Generated table syntax is invalid:\n#{syntax_output}" unless status.success?

    File.chmod(mode, temporary.path)
    File.rename(temporary.path, destination)
  end
end

unsupported_rules.verify!

buffer = StringIO.new
emit_tables(buffer, extensions, types, magics)
write_tables(options[:output], buffer.string)
warn "Skipped #{unsupported_rules.count} unsupported magic rules" if unsupported_rules.count > 0
