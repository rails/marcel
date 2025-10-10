require 'test_helper'
require 'nokogiri'

class TikaRegexTest < Marcel::TestCase
  test "converts simple pattern" do
    pattern = '^BZh[1-9]'
    result = Marcel::TikaRegex.to_ruby_regexp(pattern)
    
    assert_instance_of Regexp, result
    assert_equal(/^BZh[1-9]/, result)
  end

  test "converts Java double-escaped hex sequences" do
    # Java XML: \\x00 -> Ruby: \x00 (null byte)
    pattern = '\\\\x00\\\\x41\\\\x42'
    result = Marcel::TikaRegex.to_ruby_regexp(pattern)
    
    assert_instance_of Regexp, result
    assert result.match?("\x00AB"), "Should match null byte followed by AB"
  end

  test "converts Java double-escaped octal sequences" do
    # Java XML: \\000 -> Ruby: \000 (null byte)
    pattern = '\\\\000\\\\101\\\\102'
    result = Marcel::TikaRegex.to_ruby_regexp(pattern)
    
    assert_instance_of Regexp, result
    assert result.match?("\x00AB"), "Should match null byte followed by AB (octal)"
  end

  test "converts Java double-escaped unicode sequences" do
    # Java XML: \\u0041 -> Ruby: \u0041 (letter A)
    pattern = '\\\\u0041\\\\u0042\\\\u0043'
    result = Marcel::TikaRegex.to_ruby_regexp(pattern)
    
    assert_instance_of Regexp, result
    assert result.match?("ABC"), "Should match ABC"
  end

  test "converts Java double-escaped character classes" do
    # \\d -> \d (digit)
    pattern = 'JAVA PROFILE \\\\d\\\\.\\\\d\\\\.\\\\d'
    result = Marcel::TikaRegex.to_ruby_regexp(pattern)
    
    assert_instance_of Regexp, result
    assert result.match?("JAVA PROFILE 1.0.2"), "Should match version pattern"
    refute result.match?("JAVA PROFILE X.Y.Z"), "Should not match non-digits"
  end

  test "converts multiple escape types in one pattern" do
    pattern = '\\\\d+\\\\x00\\\\s\\\\w+'
    result = Marcel::TikaRegex.to_ruby_regexp(pattern)
    
    assert_instance_of Regexp, result
    assert result.match?("123\x00 test"), "Should match digits, null, whitespace, word chars"
  end

  test "removes multiple dotall flags" do
    pattern = '(?s)first(?s)second'
    result = Marcel::TikaRegex.to_ruby_regexp(pattern)
    
    assert_instance_of Regexp, result
    assert_equal 'firstsecond', result.source
    assert_equal Regexp::MULTILINE, result.options & Regexp::MULTILINE
  end
  
  test "returns nil for incompatible pattern" do
    # Variable-length lookbehind is not supported in Ruby
    pattern = '(?<=[\\x00][^\\x00]{0,10})[A-Z]'
    result = Marcel::TikaRegex.to_ruby_regexp(pattern)
    
    assert_nil result, "Incompatible pattern should return nil"
  end
  
  test "returns nil for nil input" do
    result = Marcel::TikaRegex.to_ruby_regexp(nil)
    assert_nil result
  end
  
  test "returns nil for empty string" do
    result = Marcel::TikaRegex.to_ruby_regexp('')
    assert_nil result
  end
  
  test "handles character class overlaps silently" do
    pattern = '[a-zA-Z][A-Za-z0-9_]'
    
    # Capture stderr to check for warnings
    old_stderr = $stderr
    $stderr = StringIO.new
    
    result = Marcel::TikaRegex.to_ruby_regexp(pattern)
    
    warnings = $stderr.string
    $stderr = old_stderr
    
    assert_instance_of Regexp, result
    assert_equal '', warnings, "Should not produce warnings"
  end
  
  test "handles multiple flags" do
    pattern = '(?i)(?s)<html>.*</html>'
    result = Marcel::TikaRegex.to_ruby_regexp(pattern)
    
    assert_instance_of Regexp, result
    assert result.match?("<HTML>\n</HTML>"), "Should be case-insensitive and multiline"
    assert result.match?("<html>\ntest\n</html>"), "Should match content across lines"
  end

  test "compiles all regex patterns from tika.xml" do
    # MIME types with known incompatible patterns
    # These patterns use Java-specific regex features not supported by Ruby
    ignore_list = %w( application/x-dbf )

    doc = Nokogiri::XML(File.new('data/tika.xml'))
    patterns_by_type = {}
    
    # Extract all regex patterns from tika.xml
    (doc/'mime-info/mime-type').each do |mime|
      type = mime['type']
      
      (mime/'magic/match[@type="regex"]').each do |match|
        patterns_by_type[type] ||= []
        patterns_by_type[type] << match['value']
      end
    end
    
    patterns_by_type.each do |mime_type, patterns|
      patterns.each do |pattern|
        next if ignore_list.include?(mime_type)
        
        result = Marcel::TikaRegex.to_ruby_regexp(pattern)
        assert_instance_of Regexp, result, "Pattern for #{mime_type} should compile to Regexp: #{pattern}"
      end
    end
  end
end
