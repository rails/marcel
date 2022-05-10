#!/usr/bin/env ruby

# Code in this file adapted from the mimemagic gem, released under the MIT License.
# Copyright (c) 2011 Daniel Mendler. Available at https://github.com/mimemagicrb/mimemagic.

require 'nokogiri'

class String
  alias inspect_old inspect

  def inspect
    str = b.inspect_old.gsub(/\\x([0-9a-f]{2})/i) do
      '\\%03o' % $1.to_i(16)
    end
    str.gsub!('"', '\'') unless str.match?(/[\\']/)
    str
  end
end

class BinaryString
  def initialize(string)
    @string = string
  end

  def inspect
    "b[#{@string.inspect}]"
  end
end

def str2int(s)
  return s.to_i(16) if s[0..1].downcase == '0x'
  return s.to_i(8) if s[0..0].downcase == '0'
  s.to_i(10)
end

def binary_strings(object)
  case object
  when Array
    object.map { |o| binary_strings(o) }
  when String
    BinaryString.new(object)
  when Numeric, Range, nil
    object
  else
    raise TypeError, "unexpected #{object.class}"
  end
end

def get_matches(parent)
  parent.elements.map {|match|
    children = get_matches(match)

    type = match['type']
    value = match['value']
    offset = match['offset'] || '0'
    offset = offset.split(':').map {|x| x.to_i }

    mask = match['mask']
    if mask && (!mask.match?(/\A0x(FF|00)*\z/) || type != 'string')
      # We only support masks of whole bytes against a string type
      next nil
    end

    offset = offset.size == 2 ? offset[0]..offset[1] : offset[0]
    case type
    when 'string', 'stringignorecase'
      value.gsub!(/\A0x([0-9a-f]+)\z/i) { [$1].pack('H*') }
      value.gsub!(/\\(x[\dA-Fa-f]{1,2}|0\d{1,3}|\d{1,3}|.)/) { eval("\"\\#{$1}\"") }

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
    end
    children.empty? ? [offset, value] : [offset, value, children]
  }.compact
end

if ARGV.size == 0
  puts "Usage: #{$0} path/to/data.xml"
  exit 1
end

extensions = {}
types = {}
magics = []

ARGV.each do |path|
  file = File.new(path)
  doc = Nokogiri::XML(file)

  (doc/'mime-info/mime-type').each do |mime|
    comments = Hash[*(mime/'_comment').map {|comment| [comment['xml:lang'], comment.inner_text] }.flatten]
    type = mime['type']
    subclass = (mime/'sub-class-of').map{|x| x['type']}
    exts = (mime/'glob').map{|x| x['pattern'] =~ /^\*\.([^\[\]]+)$/ ? $1.downcase : nil }.compact
    (mime/'magic').each do |magic|
      priority = (magic['priority'] || '50').to_i
      matches = get_matches(magic)
      magics << [priority, type, matches]
    end
    if !exts.empty?
      exts.each{|x|
        extensions[x] = type if !extensions.include?(x)
      }
      types[type] = [exts,subclass,comments[nil]]
    end
  end
end

magics = magics.sort_by { |priority, type| [-priority, type] }

common_types = [
  "image/jpeg",                                                                # .jpg
  "image/png",                                                                 # .png
  "image/gif",                                                                 # .gif
  "image/tiff",                                                                # .tiff
  "image/bmp",                                                                 # .bmp
  "image/vnd.adobe.photoshop",                                                 # .psd
  "image/webp",                                                                # .webp
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

puts "# frozen_string_literal: true"
puts ""
puts "# This file is auto-generated. Instead of editing this file, please"
puts "# add MIMEs to data/custom.xml or lib/marcel/mime_type/definitions.rb."
puts ""
puts "module Marcel"
puts "  # @private"
puts "  # :nodoc:"
puts "  EXTENSIONS = {"
extensions.keys.sort.each do |key|
  puts "    '#{key}' => '#{extensions[key]}',"
end
puts "  }"
puts "  # @private"
puts "  # :nodoc:"
puts "  TYPE_EXTS = {"
types.keys.sort.each do |key|
  exts = types[key][0].join(' ')
  comment = types[key][2]
  comment = " # #{comment.tr("\n", " ")}" if comment
  puts "    '#{key}' => %w(#{exts}),#{comment}"
end
puts "  }"
puts "  TYPE_PARENTS = {"
types.keys.sort.each do |key|
  parents = types[key][1].sort.join(' ')
  unless parents.empty?
    puts "    '#{key}' => %w(#{parents}),"
  end
end
puts "  }"
puts "  b = Hash.new { |h, k| h[k] = k.b.freeze }"
puts "  # @private"
puts "  # :nodoc:"
puts "  MAGIC = ["
magics.each do |priority, type, matches|
  puts "    ['#{type}', #{binary_strings(matches).inspect}],"
end
puts "  ]"
puts "end"
