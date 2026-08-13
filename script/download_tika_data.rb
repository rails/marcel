#!/usr/bin/env ruby
require 'digest'
require 'net/http'
require 'uri'

# To update the MIME database, review a new Tika commit and update both values.
TIKA_COMMIT = "c29724782854bb5a319f4a1940d0828a58ace3f9".freeze
TIKA_DATA_SHA256 = "b213c35123f215e11a9fa12d7907c9bb0a5b79214a89eeaf343984ba69143e6d".freeze
TIKA_URL = "https://raw.githubusercontent.com/apache/tika/#{TIKA_COMMIT}/tika-core/src/main/resources/org/apache/tika/mime/tika-mimetypes.xml".freeze
TIKA_PROVENANCE = "<!-- Downloaded from #{TIKA_URL} -->\n".freeze
TIKA_PREAMBLE = /\A(?:<\?xml[^\n]*\?>\n)?/.freeze

def verify_tika_data(data, source)
  checksum = Digest::SHA256.hexdigest(data)
  return if checksum == TIKA_DATA_SHA256

  abort "Unexpected Tika MIME data checksum for #{source}: #{checksum}"
end

def annotate_tika_data(data)
  offset = TIKA_PREAMBLE.match(data).end(0)
  data.dup.insert(offset, TIKA_PROVENANCE)
end

def verify_annotated_tika_data(data, source)
  offset = TIKA_PREAMBLE.match(data).end(0)
  unless data.byteslice(offset, TIKA_PROVENANCE.bytesize) == TIKA_PROVENANCE
    abort "Unexpected Tika provenance comment in #{source}"
  end

  upstream_data = data.dup
  upstream_data.slice!(offset, TIKA_PROVENANCE.bytesize)
  verify_tika_data(upstream_data, source)
end

if ARGV.first == "--verify"
  abort "Usage: #{$0} --verify path/to/tika.xml" unless ARGV.length == 2

  verify_annotated_tika_data(File.binread(ARGV.last), ARGV.last)
  exit
elsif ARGV.any?
  abort "Usage: #{$0} [--verify path/to/tika.xml]"
end

url = URI(TIKA_URL)
data = Net::HTTP.get_response(url).tap(&:value).body
verify_tika_data(data, url)

puts annotate_tika_data(data)
