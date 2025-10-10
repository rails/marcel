# frozen_string_literal: true

module Marcel
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

      # I know, I know... this is awful, but the patterns come from Apache Tika
      # and we are getting warnings about character class overlaps, so we'll
      # suppress warnings for this Regexp compilation.
      # I'm open to better ideas.
      old_verbose = $VERBOSE
      $VERBOSE = nil
      
      Regexp.new(processed, flags).freeze
    rescue RegexpError
      nil
    ensure
      $VERBOSE = old_verbose
    end
  end
end
