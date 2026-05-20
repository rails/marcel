require 'test_helper'
require 'rack'

class Marcel::MimeType::MagicTest < Marcel::TestCase
  # These fixtures should be recognisable given only their contents. Where a generic type
  # has more specific subclasses (such as application/zip), these subclasses cannot usually
  # be recognised by magic alone; their name is also needed to correctly identify them.
  each_content_type_fixture('magic') do |file, name, content_type|
    test "gets type for #{content_type} by using only magic bytes #{name}" do
      actual_type = raw_type(Marcel::MimeType.for(file))
      assert_equal content_type, actual_type, "Expected #{file} to be #{content_type}, but was #{actual_type}"
    end
  end

  test "add and remove type" do
    Marcel::Magic.add('application/x-my-thing', extensions: 'mtg', parents: 'application/json')
    Marcel::Magic.remove('application/x-my-thing')
  end

  test "#extensions" do
    json = Marcel::Magic.by_extension('json')
    assert_equal ['json'], json.extensions
  end

  test ".child?" do
    assert Marcel::Magic.child?('text/csv', 'text/plain')
    refute Marcel::Magic.child?('text/plain', 'text/csv')
  end

  test "no Ruby 3.4 frozen string warnings with StringIO" do
    # Ruby 3.4 warns about code that will break when frozen string literals become default
    # This test ensures marcel handles StringIO with frozen strings correctly
    content = "Test content for mime detection"
    io = StringIO.new(content)

    # Capture warnings
    warnings = []
    original_stderr = $stderr
    $stderr = StringIO.new

    begin
      Marcel::MimeType.for(io)
      warnings = $stderr.string.lines.grep(/marcel.*magic\.rb.*frozen/)
    ensure
      $stderr = original_stderr
    end

    assert_empty warnings, "Expected no frozen string warnings, but got:\n#{warnings.join}"
  end

  test "none of the regex patterns should match random test data" do
    ignore_list = %w( application/x-dbf )

    extract_regexes = lambda do |matching_rules, collected = []|
      matching_rules.each do |offset, value, children|
        collected << [offset, value] if value.is_a?(Regexp)
        extract_regexes.call(children, collected) if children
      end
      collected
    end

    # Use a test string that's very unlikely to match any file format regex
    # Using only high Unicode characters and very specific patterns
    test_data = "🇨🇭 \xFF\xFE\x03\x05\x06🧀 cheese\x06\x07\x03"

    Marcel::MAGIC.each do |type, matching_rules|
      next if ignore_list.include?(type)
      regexes = extract_regexes.call(matching_rules)

      result = Marcel::Magic.send(:magic_match_io, StringIO.new(test_data), regexes, "".b)
      assert_equal false, result, "Test data unexpectedly matched a file format regexp (#{type}, #{regexes.inspect})"
    end
  end

  test "nested match: parent AND child must both match" do
    # Rule: offset 0 matches "AAA" AND offset 3 matches "BBB"
    # This should match "AAABBB" but not "AAA" alone
    test_rules = [
      [0, "AAA".b, [[3, "BBB".b]]]
    ]
    
    buffer = (+"").encode(Encoding::BINARY)
    
    # Should match when both parent and child match
    io1 = StringIO.new("AAABBB")
    assert Marcel::Magic.send(:magic_match_io, io1, test_rules, buffer),
           "Should match when parent and child both match"
    
    # Should NOT match when parent matches but child doesn't
    io2 = StringIO.new("AAAXXX")
    refute Marcel::Magic.send(:magic_match_io, io2, test_rules, buffer),
           "Should not match when parent matches but child doesn't"
  end

  test "sibling matches use OR logic" do
    # Two sibling rules: either can match
    # Rule 1: offset 0 matches "XXX"
    # Rule 2: offset 0 matches "YYY"
    test_rules = [
      [0, "XXX".b],
      [0, "YYY".b]
    ]
    
    buffer = (+"").encode(Encoding::BINARY)
    
    # Should match via first sibling
    io1 = StringIO.new("XXX")
    assert Marcel::Magic.send(:magic_match_io, io1, test_rules, buffer),
           "Should match via first sibling rule"
    
    # Should match via second sibling
    io2 = StringIO.new("YYY")
    assert Marcel::Magic.send(:magic_match_io, io2, test_rules, buffer),
           "Should match via second sibling rule"
    
    # Should NOT match when no sibling matches
    io3 = StringIO.new("ZZZ")
    refute Marcel::Magic.send(:magic_match_io, io3, test_rules, buffer),
           "Should not match when no sibling rule matches"
  end

  test "parent with multiple child alternatives (OR)" do
    # Test complex nested structure: parent AND (child1 OR child2)
    # Parent at offset 0 matches "ROOT"
    # Child option 1: offset 4 matches "OPT1"
    # Child option 2: offset 4 matches "OPT2"
    test_rules = [
      [0, "ROOT".b, [
        [4, "OPT1".b],  # First child option
        [4, "OPT2".b]   # Second child option (sibling OR)
      ]]
    ]
    
    buffer = (+"").encode(Encoding::BINARY)
    
    # Should match when parent and first child match
    io1 = StringIO.new("ROOTOPT1")
    assert Marcel::Magic.send(:magic_match_io, io1, test_rules, buffer),
           "Should match when parent and first child match"
    
    # Should match when parent and second child match
    io2 = StringIO.new("ROOTOPT2")
    assert Marcel::Magic.send(:magic_match_io, io2, test_rules, buffer),
           "Should match when parent and second child match"
    
    # Should NOT match when parent matches but no child matches
    io3 = StringIO.new("ROOTXXXX")
    refute Marcel::Magic.send(:magic_match_io, io3, test_rules, buffer),
           "Should not match when parent matches but no child matches"
  end

  test "complex nested structure with multiple levels" do
    # Parent AND (Child AND Grandchild)
    # offset 0: "AAA", offset 3: "BBB", offset 6: "CCC"
    test_rules = [
      [0, "AAA".b, [
        [3, "BBB".b, [
          [6, "CCC".b]
        ]]
      ]]
    ]
    
    buffer = (+"").encode(Encoding::BINARY)
    
    # Should match when all levels match
    io1 = StringIO.new("AAABBBCCC")
    assert Marcel::Magic.send(:magic_match_io, io1, test_rules, buffer),
           "Should match when all nested levels match"
    
    # Should NOT match when grandchild doesn't match
    io2 = StringIO.new("AAABBBXXX")
    refute Marcel::Magic.send(:magic_match_io, io2, test_rules, buffer),
           "Should not match when deepest child doesn't match"
  end
end
