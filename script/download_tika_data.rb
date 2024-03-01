#!/usr/bin/env ruby
require 'net/http'
require 'uri'

url = URI("https://raw.githubusercontent.com/apache/tika/main/tika-core/src/main/resources/org/apache/tika/mime/tika-mimetypes.xml")
data = Net::HTTP.get_response(url).tap(&:value).body

# Insert a comment indicating provenance
data.sub! /\A(?:<\?xml.+\?>\n)?/, "\\&<!-- Downloaded at #{Time.now.utc} from #{url} -->\n"

puts data
